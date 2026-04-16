const PREAMBLE_SAMPLES = 16;
const LONG_FRAME_BITS = 112;
const LONG_FRAME_SAMPLES = PREAMBLE_SAMPLES + (LONG_FRAME_BITS * 2);
const CPR_SCALE = 131072;
const AIRCRAFT_PRUNE_MS = 5 * 60 * 1000;
const SNAPSHOT_INTERVAL_MS = 1000;
const CALLSIGN_TABLE = "#ABCDEFGHIJKLMNOPQRSTUVWXYZ#####_###############0123456789######";
const MODE_S_GENERATOR = "1111111111111010000001001";
const GENERATOR_BITS = MODE_S_GENERATOR.split("").map((bit) => Number.parseInt(bit, 10));
const POWER_LUT = new Float32Array(256);

for (let index = 0; index < 256; index += 1) {
  const centered = index - 127.5;
  POWER_LUT[index] = centered * centered;
}

const state = createState();

self.addEventListener("message", (event) => {
  const payload = event.data || {};

  if (payload.type === "reset") {
    resetState();
    return;
  }

  if (payload.type === "samples" && payload.data instanceof ArrayBuffer) {
    processSamples(payload.data);
  }
});

function createState() {
  return {
    aircraft: new Map(),
    candidateFrameCount: 0,
    validFrameCount: 0,
    positionFixCount: 0,
    tailMagnitudes: new Float32Array(0),
    lastSnapshotAt: 0
  };
}

function resetState() {
  const fresh = createState();
  state.aircraft = fresh.aircraft;
  state.candidateFrameCount = fresh.candidateFrameCount;
  state.validFrameCount = fresh.validFrameCount;
  state.positionFixCount = fresh.positionFixCount;
  state.tailMagnitudes = fresh.tailMagnitudes;
  state.lastSnapshotAt = fresh.lastSnapshotAt;
  postDecoderStatus("Decoder worker is ready.");
}

function processSamples(arrayBuffer) {
  try {
    const bytes = new Uint8Array(arrayBuffer);
    const magnitudes = bytesToMagnitudes(bytes);
    const merged = mergeMagnitudes(state.tailMagnitudes, magnitudes);
    decodeFrames(merged);
    state.tailMagnitudes = merged.slice(Math.max(0, merged.length - 512));
    emitSnapshot(false);
  } catch (error) {
    postError(error && error.message ? error.message : "The browser decoder failed while processing samples.");
  }
}

function bytesToMagnitudes(bytes) {
  const magnitudeCount = Math.floor(bytes.length / 2);
  const magnitudes = new Float32Array(magnitudeCount);

  for (let sampleIndex = 0, byteIndex = 0; sampleIndex < magnitudeCount; sampleIndex += 1, byteIndex += 2) {
    magnitudes[sampleIndex] = POWER_LUT[bytes[byteIndex]] + POWER_LUT[bytes[byteIndex + 1]];
  }

  return magnitudes;
}

function mergeMagnitudes(prefix, current) {
  if (!prefix.length) {
    return current;
  }

  const merged = new Float32Array(prefix.length + current.length);
  merged.set(prefix, 0);
  merged.set(current, prefix.length);
  return merged;
}

function decodeFrames(magnitudes) {
  const limit = magnitudes.length - LONG_FRAME_SAMPLES - 2;

  for (let offset = 0; offset < limit; offset += 1) {
    if (!isLikelyPreamble(magnitudes, offset)) {
      continue;
    }

    state.candidateFrameCount += 1;
    const messageBytes = decodeLongFrame(magnitudes, offset);
    if (!messageBytes) {
      continue;
    }

    const bitString = bytesToBitString(messageBytes);
    if (crcRemainder(bitString) !== 0) {
      continue;
    }

    const df = bitsToInt(bitString, 1, 5);
    if (df !== 17 && df !== 18) {
      continue;
    }

    state.validFrameCount += 1;
    decodeAdsbMessage(bitString, messageBytes);
    offset += LONG_FRAME_SAMPLES - 1;
  }
}

function isLikelyPreamble(magnitudes, offset) {
  const p0 = magnitudes[offset];
  const p1 = magnitudes[offset + 1];
  const p2 = magnitudes[offset + 2];
  const p3 = magnitudes[offset + 3];
  const p4 = magnitudes[offset + 4];
  const p5 = magnitudes[offset + 5];
  const p6 = magnitudes[offset + 6];
  const p7 = magnitudes[offset + 7];
  const p8 = magnitudes[offset + 8];
  const p9 = magnitudes[offset + 9];
  const p10 = magnitudes[offset + 10];

  const signal = (p0 + p2 + p7 + p9) / 4;
  const noise = (p1 + p3 + p4 + p5 + p6 + p8 + p10) / 7;

  if (!(signal > noise * 2.5)) {
    return false;
  }

  return (
    p0 > p1 &&
    p2 > p3 &&
    p7 > p8 &&
    p9 > p10 &&
    p4 < signal &&
    p5 < signal &&
    p6 < signal
  );
}

function decodeLongFrame(magnitudes, offset) {
  const bytes = new Uint8Array(14);
  const dataStart = offset + PREAMBLE_SAMPLES;

  for (let bitIndex = 0; bitIndex < LONG_FRAME_BITS; bitIndex += 1) {
    const first = magnitudes[dataStart + (bitIndex * 2)];
    const second = magnitudes[dataStart + (bitIndex * 2) + 1];

    if (first === second) {
      return null;
    }

    if (first > second) {
      const byteIndex = bitIndex >> 3;
      const bitOffset = 7 - (bitIndex & 7);
      bytes[byteIndex] |= (1 << bitOffset);
    }
  }

  return bytes;
}

function decodeAdsbMessage(bitString, messageBytes) {
  const icao = bytesToHex(messageBytes.slice(1, 4));
  const typeCode = bitsToInt(bitString, 33, 37);
  const meBits = bitString.slice(32, 88);
  const now = Date.now();

  const aircraft = state.aircraft.get(icao) || createAircraft(icao);
  aircraft.lastSeenAt = now;
  aircraft.messageCount += 1;

  if (typeCode >= 1 && typeCode <= 4) {
    const flight = decodeCallsign(meBits);
    if (flight) {
      aircraft.flight = flight;
    }
  } else if ((typeCode >= 9 && typeCode <= 18) || (typeCode >= 20 && typeCode <= 22)) {
    decodeAirbornePosition(aircraft, meBits, typeCode, now);
  } else if (typeCode === 19) {
    decodeVelocity(aircraft, meBits);
  }

  state.aircraft.set(icao, aircraft);
}

function createAircraft(hex) {
  return {
    hex,
    flight: "",
    alt_baro: null,
    alt_geom: null,
    gs: null,
    tas: null,
    track: null,
    verticalRate: null,
    lat: null,
    lon: null,
    lastSeenAt: 0,
    messageCount: 0,
    cprEven: null,
    cprOdd: null
  };
}

function decodeCallsign(meBits) {
  let callsign = "";

  for (let start = 8; start < 56; start += 6) {
    const value = Number.parseInt(meBits.slice(start, start + 6), 2);
    const mapped = CALLSIGN_TABLE[value] || " ";
    callsign += mapped === "#" || mapped === "_" ? " " : mapped;
  }

  return callsign.trim();
}

function decodeAirbornePosition(aircraft, meBits, typeCode, now) {
  const altitudeBits = meBits.slice(8, 20);
  const isOddFrame = meBits[21] === "1";
  const latCpr = Number.parseInt(meBits.slice(22, 39), 2);
  const lonCpr = Number.parseInt(meBits.slice(39, 56), 2);

  if (typeCode >= 9 && typeCode <= 18) {
    const altitude = decodeBarometricAltitude(altitudeBits);
    if (altitude !== null) {
      aircraft.alt_baro = altitude;
    }
  }

  const frame = {
    latCpr,
    lonCpr,
    timestamp: now
  };

  if (isOddFrame) {
    aircraft.cprOdd = frame;
  } else {
    aircraft.cprEven = frame;
  }

  const position = tryDecodePosition(aircraft, isOddFrame);
  if (!position) {
    return;
  }

  if (!Number.isFinite(aircraft.lat) || !Number.isFinite(aircraft.lon) || aircraft.lat !== position.lat || aircraft.lon !== position.lon) {
    state.positionFixCount += 1;
  }

  aircraft.lat = position.lat;
  aircraft.lon = position.lon;
}

function decodeBarometricAltitude(altitudeBits) {
  if (altitudeBits.length !== 12) {
    return null;
  }

  if (altitudeBits[7] !== "1") {
    return null;
  }

  const compact = altitudeBits.slice(0, 7) + altitudeBits.slice(8);
  return (Number.parseInt(compact, 2) * 25) - 1000;
}

function tryDecodePosition(aircraft, isOddFrame) {
  const even = aircraft.cprEven;
  const odd = aircraft.cprOdd;

  if (even && odd && Math.abs(even.timestamp - odd.timestamp) <= 10000) {
    return decodeGlobalCpr(even, odd);
  }

  if (Number.isFinite(aircraft.lat) && Number.isFinite(aircraft.lon)) {
    const frame = isOddFrame ? odd : even;
    if (frame) {
      return decodeLocalCpr(frame, isOddFrame, aircraft.lat, aircraft.lon);
    }
  }

  return null;
}

function decodeGlobalCpr(even, odd) {
  const latEven = even.latCpr / CPR_SCALE;
  const latOdd = odd.latCpr / CPR_SCALE;
  const lonEven = even.lonCpr / CPR_SCALE;
  const lonOdd = odd.lonCpr / CPR_SCALE;
  const j = Math.floor(((59 * latEven) - (60 * latOdd)) + 0.5);

  let decodedLatEven = (360 / 60) * (positiveMod(j, 60) + latEven);
  let decodedLatOdd = (360 / 59) * (positiveMod(j, 59) + latOdd);

  if (decodedLatEven >= 270) {
    decodedLatEven -= 360;
  }

  if (decodedLatOdd >= 270) {
    decodedLatOdd -= 360;
  }

  if (cprNL(decodedLatEven) !== cprNL(decodedLatOdd)) {
    return null;
  }

  const useEven = even.timestamp >= odd.timestamp;
  const latitude = useEven ? decodedLatEven : decodedLatOdd;
  const nl = cprNL(latitude);
  const ni = Math.max(useEven ? nl : nl - 1, 1);
  const m = Math.floor((((lonEven * Math.max(nl - 1, 0)) - (lonOdd * nl)) + 0.5));
  let longitude;

  if (useEven) {
    longitude = (360 / ni) * (positiveMod(m, ni) + lonEven);
  } else {
    longitude = (360 / ni) * (positiveMod(m, ni) + lonOdd);
  }

  if (longitude > 180) {
    longitude -= 360;
  }

  return {
    lat: roundCoordinate(latitude),
    lon: roundCoordinate(longitude)
  };
}

function decodeLocalCpr(frame, isOddFrame, latRef, lonRef) {
  const dLat = isOddFrame ? (360 / 59) : (360 / 60);
  const lat = dLat * (
    Math.floor(latRef / dLat)
    + Math.floor((positiveMod(latRef, dLat) / dLat) - (frame.latCpr / CPR_SCALE) + 0.5)
    + (frame.latCpr / CPR_SCALE)
  );
  const adjustedLat = lat >= 270 ? lat - 360 : lat;
  const nl = cprNL(adjustedLat);
  const ni = Math.max(isOddFrame ? nl - 1 : nl, 1);
  const dLon = 360 / ni;
  let longitude = dLon * (
    Math.floor(lonRef / dLon)
    + Math.floor((positiveMod(lonRef, dLon) / dLon) - (frame.lonCpr / CPR_SCALE) + 0.5)
    + (frame.lonCpr / CPR_SCALE)
  );

  if (longitude > 180) {
    longitude -= 360;
  }

  return {
    lat: roundCoordinate(adjustedLat),
    lon: roundCoordinate(longitude)
  };
}

function decodeVelocity(aircraft, meBits) {
  const subtype = Number.parseInt(meBits.slice(5, 8), 2);

  if (subtype === 1 || subtype === 2) {
    const scale = subtype === 2 ? 4 : 1;
    const sew = Number.parseInt(meBits.slice(13, 14), 2);
    const vew = Number.parseInt(meBits.slice(14, 24), 2);
    const sns = Number.parseInt(meBits.slice(24, 25), 2);
    const vns = Number.parseInt(meBits.slice(25, 35), 2);

    if (vew > 0 && vns > 0) {
      const vx = (sew === 0 ? 1 : -1) * scale * (vew - 1);
      const vy = (sns === 0 ? 1 : -1) * scale * (vns - 1);
      aircraft.gs = Math.round(Math.hypot(vx, vy));
      aircraft.track = roundHeading(Math.atan2(vx, vy) * 180 / Math.PI);
    }
  } else if (subtype === 3 || subtype === 4) {
    const scale = subtype === 4 ? 4 : 1;
    const headingStatus = Number.parseInt(meBits.slice(13, 14), 2);
    const headingValue = Number.parseInt(meBits.slice(14, 24), 2);
    const airspeedValue = Number.parseInt(meBits.slice(25, 35), 2);

    if (headingStatus === 1) {
      aircraft.track = roundHeading((headingValue * 360) / 1024);
    }

    if (airspeedValue > 0) {
      aircraft.tas = scale * (airspeedValue - 1);
      aircraft.gs = aircraft.tas;
    }
  }

  const verticalRateSign = Number.parseInt(meBits.slice(36, 37), 2);
  const verticalRateValue = Number.parseInt(meBits.slice(37, 46), 2);

  if (verticalRateValue > 0) {
    aircraft.verticalRate = (verticalRateSign === 0 ? 1 : -1) * 64 * (verticalRateValue - 1);
  }
}

function cprNL(latitude) {
  const absoluteLatitude = Math.abs(latitude);
  if (absoluteLatitude >= 87) {
    return 1;
  }

  const nz = 15;
  const angle = Math.PI / 180 * absoluteLatitude;
  const denominator = Math.cos(angle) ** 2;
  if (denominator <= 0) {
    return 1;
  }

  const a = 1 - Math.cos(Math.PI / (2 * nz));
  const ratio = 1 - (a / denominator);
  const clamped = Math.min(1, Math.max(-1, ratio));
  return Math.floor((2 * Math.PI) / Math.acos(clamped));
}

function crcRemainder(bitString) {
  const data = bitString.split("").map((bit) => Number.parseInt(bit, 10));

  for (let index = 0; index <= data.length - GENERATOR_BITS.length; index += 1) {
    if (data[index] !== 1) {
      continue;
    }

    for (let bitIndex = 0; bitIndex < GENERATOR_BITS.length; bitIndex += 1) {
      data[index + bitIndex] ^= GENERATOR_BITS[bitIndex];
    }
  }

  return data.slice(-24).some((bit) => bit !== 0) ? 1 : 0;
}

function emitSnapshot(force) {
  const now = Date.now();
  if (!force && now - state.lastSnapshotAt < SNAPSHOT_INTERVAL_MS) {
    return;
  }

  pruneAircraft(now);
  state.lastSnapshotAt = now;

  const aircraft = [...state.aircraft.values()].map((entry) => ({
    hex: entry.hex,
    flight: entry.flight,
    alt_baro: entry.alt_baro,
    alt_geom: entry.alt_geom,
    gs: entry.gs,
    tas: entry.tas,
    track: entry.track,
    verticalRate: entry.verticalRate,
    lat: entry.lat,
    lon: entry.lon,
    seen: roundSeconds((now - entry.lastSeenAt) / 1000)
  }));

  self.postMessage({
    type: "snapshot",
    aircraft,
    aircraftCount: aircraft.length,
    candidateFrameCount: state.candidateFrameCount,
    validFrameCount: state.validFrameCount,
    positionFixCount: state.positionFixCount
  });
}

function pruneAircraft(now) {
  for (const [hex, aircraft] of state.aircraft.entries()) {
    if (now - aircraft.lastSeenAt > AIRCRAFT_PRUNE_MS) {
      state.aircraft.delete(hex);
    }
  }
}

function bytesToBitString(bytes) {
  let bitString = "";
  for (const byte of bytes) {
    bitString += byte.toString(2).padStart(8, "0");
  }
  return bitString;
}

function bitsToInt(bitString, startBit, endBit) {
  return Number.parseInt(bitString.slice(startBit - 1, endBit), 2);
}

function bytesToHex(bytes) {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("").toUpperCase();
}

function positiveMod(value, modulus) {
  if (modulus === 0) {
    return 0;
  }

  return ((value % modulus) + modulus) % modulus;
}

function roundCoordinate(value) {
  return Math.round(value * 100000) / 100000;
}

function roundHeading(value) {
  const normalized = ((value % 360) + 360) % 360;
  return Math.round(normalized * 10) / 10;
}

function roundSeconds(value) {
  return Math.round(value * 10) / 10;
}

function postDecoderStatus(message) {
  self.postMessage({ type: "decoder-status", message });
}

function postError(message) {
  self.postMessage({ type: "error", message });
}
