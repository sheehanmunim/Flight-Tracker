import { RTL2832U } from "https://cdn.jsdelivr.net/npm/@jtarrio/webrtlsdr@2.0.4/dist/rtlsdr/rtl2832u.js";

const RTL_FILTERS = [
  { vendorId: 0x0bda, productId: 0x2832 },
  { vendorId: 0x0bda, productId: 0x2838 }
];

const params = new URLSearchParams(window.location.search);
const dashboardKey = params.get("key") || window.localStorage.getItem("flight-tracker-dashboard-key") || "";
const startBtn = document.getElementById("startBtn");
const stopBtn = document.getElementById("stopBtn");
const ppmInput = document.getElementById("ppmInput");
const sampleRateInput = document.getElementById("sampleRateInput");
const dashboardLink = document.getElementById("dashboardLink");
const supportOutput = document.getElementById("supportOutput");
const deviceOutput = document.getElementById("deviceOutput");
const activity = document.getElementById("activity");
const tableHost = document.getElementById("tableHost");
const statusValue = document.getElementById("statusValue");
const aircraftCount = document.getElementById("aircraftCount");
const frameCount = document.getElementById("frameCount");
const positionCount = document.getElementById("positionCount");
const updatedAt = document.getElementById("updatedAt");

let receiverWorker = null;
let radio = null;
let selectedDevice = null;
let receiverRunning = false;
let readLoopPromise = null;
let actualSampleRate = 0;
let actualCenterFrequency = 0;

if (dashboardKey) {
  window.localStorage.setItem("flight-tracker-dashboard-key", dashboardKey);
  dashboardLink.href = `/?key=${encodeURIComponent(dashboardKey)}`;
}

startBtn.addEventListener("click", async () => {
  await startBrowserReceiver();
});

stopBtn.addEventListener("click", async () => {
  await stopBrowserReceiver(false);
});

window.addEventListener("pagehide", () => {
  void stopBrowserReceiver(true);
});

async function startBrowserReceiver() {
  if (receiverRunning) {
    renderActivity("Browser receiver is already running.");
    return;
  }

  if (!window.isSecureContext || !("usb" in navigator)) {
    renderActivity("WebUSB is not available in this browser context. Use desktop Chromium on https:// or localhost.");
    await describeSupport();
    return;
  }

  setBusy(true);
  renderStatus("Authorizing", "status-warn");
  renderActivity("Requesting access to the RTL-SDR...");

  try {
    selectedDevice = await ensureAuthorizedDevice();
    renderDevice(selectedDevice);

    renderActivity("Opening the SDR and configuring the browser receiver...");
    const ppm = Number.parseFloat(ppmInput.value || "0");
    const requestedSampleRate = clampSampleRate(Number.parseInt(sampleRateInput.value || "2000000", 10));

    radio = await RTL2832U.open(selectedDevice);
    await radio.setFrequencyCorrection(Number.isFinite(ppm) ? ppm : 0);
    actualSampleRate = await radio.setSampleRate(requestedSampleRate);
    actualCenterFrequency = await radio.setCenterFrequency(1090000000);
    await radio.setGain(null);
    await radio.resetBuffer();

    receiverWorker = new Worker("./browser-receiver-worker.js", { type: "module" });
    receiverWorker.addEventListener("message", handleWorkerMessage);
    receiverWorker.addEventListener("error", (event) => {
      renderStatus("Error", "status-error");
      renderActivity(event.message || "The browser decoder worker crashed.");
    });
    receiverWorker.postMessage({ type: "reset" });

    receiverRunning = true;
    setBusy(false);
    stopBtn.disabled = false;
    renderStatus("Running", "status-ok");
    renderActivity("Browser receiver is running. Reading IQ samples from the USB dongle and decoding ADS-B in a worker.");
    await describeSupport();
    renderDevice(selectedDevice, {
      sampleRate: actualSampleRate,
      centerFrequency: actualCenterFrequency,
      ppm
    });

    readLoopPromise = pumpSamples();
  } catch (error) {
    await cleanupReceiver();
    setBusy(false);
    renderStatus("Error", "status-error");
    renderActivity(error && error.message ? error.message : "The browser receiver could not start.");
    await describeSupport();
  }
}

async function stopBrowserReceiver(quiet) {
  if (!radio && !receiverWorker && !receiverRunning) {
    if (!quiet) {
      renderActivity("Browser receiver is already stopped.");
    }
    return;
  }

  receiverRunning = false;
  setBusy(true);
  renderStatus("Stopping", "status-warn");

  try {
    if (radio) {
      try {
        await radio.close();
      } catch {
        // Ignore shutdown errors while releasing the USB device.
      }
    }

    if (readLoopPromise) {
      try {
        await readLoopPromise;
      } catch {
        // Ignore loop shutdown errors; the device may have been closed mid-read.
      }
    }
  } finally {
    await cleanupReceiver();
    setBusy(false);
    renderStatus("Idle", "");
    if (!quiet) {
      renderActivity("Browser receiver stopped.");
    }
    await describeSupport();
  }
}

async function cleanupReceiver() {
  if (receiverWorker) {
    receiverWorker.terminate();
  }

  receiverWorker = null;
  radio = null;
  readLoopPromise = null;
  receiverRunning = false;
  actualSampleRate = 0;
  actualCenterFrequency = 0;
  stopBtn.disabled = true;
  aircraftCount.textContent = "0";
  frameCount.textContent = "0";
  positionCount.textContent = "0";
  updatedAt.textContent = "Waiting";
  tableHost.className = "empty";
  tableHost.textContent = "Press Start Browser Receiver to authorize the USB dongle and begin decoding.";
}

async function pumpSamples() {
  try {
    while (receiverRunning && radio && receiverWorker) {
      const block = await radio.readSamples(262144);
      receiverWorker.postMessage(
        {
          type: "samples",
          data: block.data
        },
        [block.data]
      );
    }
  } catch (error) {
    if (receiverRunning) {
      renderStatus("Error", "status-error");
      renderActivity(error && error.message ? error.message : "The browser receiver stopped while reading samples.");
      await cleanupReceiver();
      setBusy(false);
      await describeSupport();
    }
  }
}

function handleWorkerMessage(event) {
  const payload = event.data || {};

  if (payload.type === "snapshot") {
    renderSnapshot(payload);
    return;
  }

  if (payload.type === "decoder-status") {
    renderActivity(payload.message || "Decoder status updated.");
    return;
  }

  if (payload.type === "error") {
    renderStatus("Error", "status-error");
    renderActivity(payload.message || "The browser decoder reported an error.");
  }
}

async function ensureAuthorizedDevice() {
  const existing = (await navigator.usb.getDevices()).find(matchesRtlDevice);
  if (existing) {
    return existing;
  }

  return await navigator.usb.requestDevice({ filters: RTL_FILTERS });
}

function matchesRtlDevice(device) {
  return RTL_FILTERS.some((filter) => (
    device.vendorId === filter.vendorId && device.productId === filter.productId
  ));
}

function clampSampleRate(value) {
  if (!Number.isFinite(value)) {
    return 2000000;
  }

  return Math.max(1000000, Math.min(3200000, value));
}

function renderSnapshot(payload) {
  const aircraft = [...(payload.aircraft || [])]
    .sort((left, right) => {
      const leftScore = Number.isFinite(left.seen) ? left.seen : Number.MAX_SAFE_INTEGER;
      const rightScore = Number.isFinite(right.seen) ? right.seen : Number.MAX_SAFE_INTEGER;
      return leftScore - rightScore;
    })
    .slice(0, 75);

  aircraftCount.textContent = String(payload.aircraftCount || aircraft.length);
  frameCount.textContent = String(payload.validFrameCount || 0);
  positionCount.textContent = String(payload.positionFixCount || 0);
  updatedAt.textContent = new Date().toLocaleTimeString();

  if (!aircraft.length) {
    tableHost.className = "empty";
    tableHost.textContent = "The receiver is running but no valid aircraft have been decoded yet. Give it a moment and make sure the antenna is connected.";
    return;
  }

  tableHost.className = "";
  tableHost.innerHTML = `
    <table>
      <thead>
        <tr>
          <th>Flight</th>
          <th>Hex</th>
          <th>Altitude</th>
          <th>Speed</th>
          <th>Track</th>
          <th>Vertical</th>
          <th>Position</th>
          <th>Seen</th>
        </tr>
      </thead>
      <tbody>
        ${aircraft.map(renderAircraftRow).join("")}
      </tbody>
    </table>`;
}

function renderAircraftRow(aircraft) {
  const flight = (aircraft.flight || "").trim() || "Unknown";
  const altitude = aircraft.alt_baro ?? aircraft.alt_geom ?? "N/A";
  const speed = aircraft.gs ?? aircraft.tas ?? "N/A";
  const track = Number.isFinite(aircraft.track) ? `${aircraft.track.toFixed(1)} deg` : "N/A";
  const verticalRate = Number.isFinite(aircraft.verticalRate) ? `${aircraft.verticalRate} ft/min` : "N/A";
  const lat = Number.isFinite(aircraft.lat) ? aircraft.lat.toFixed(4) : "";
  const lon = Number.isFinite(aircraft.lon) ? aircraft.lon.toFixed(4) : "";
  const position = lat && lon ? `${lat}, ${lon}` : "No fix";
  const seen = Number.isFinite(aircraft.seen) ? `${aircraft.seen.toFixed(1)}s ago` : "N/A";

  return `
    <tr>
      <td data-label="Flight"><span class="pill">${escapeHtml(flight)}</span></td>
      <td data-label="Hex">${escapeHtml((aircraft.hex || "").toUpperCase() || "N/A")}</td>
      <td data-label="Altitude">${escapeHtml(String(altitude))}</td>
      <td data-label="Speed">${escapeHtml(String(speed))}</td>
      <td data-label="Track">${escapeHtml(track)}</td>
      <td data-label="Vertical">${escapeHtml(verticalRate)}</td>
      <td data-label="Position">${escapeHtml(position)}</td>
      <td data-label="Seen">${escapeHtml(seen)}</td>
    </tr>`;
}

function renderDevice(device, runtime = null) {
  const lines = [
    `Product: ${device.productName || "Unknown"}`,
    `Manufacturer: ${device.manufacturerName || "Unknown"}`,
    `Vendor ID: 0x${device.vendorId.toString(16).padStart(4, "0")}`,
    `Product ID: 0x${device.productId.toString(16).padStart(4, "0")}`
  ];

  if (device.serialNumber) {
    lines.push(`Serial: ${device.serialNumber}`);
  }

  if (runtime) {
    lines.push("");
    lines.push(`Actual sample rate: ${runtime.sampleRate || "Unknown"} samples/sec`);
    lines.push(`Center frequency: ${runtime.centerFrequency || "Unknown"} Hz`);
    lines.push(`PPM correction: ${runtime.ppm}`);
    lines.push("Gain: Auto");
  }

  deviceOutput.textContent = lines.join("\n");
}

function renderStatus(text, className) {
  statusValue.textContent = text;
  statusValue.className = `value ${className || ""}`.trim();
}

function renderActivity(message) {
  activity.textContent = message;
}

async function describeSupport() {
  const authorizedCount = "usb" in navigator ? (await navigator.usb.getDevices()).filter(matchesRtlDevice).length : 0;
  supportOutput.textContent = [
    `Secure context: ${window.isSecureContext ? "yes" : "no"}`,
    `navigator.usb available: ${"usb" in navigator ? "yes" : "no"}`,
    `Authorized RTL-SDR devices: ${authorizedCount}`,
    `User agent: ${navigator.userAgent}`,
    "",
    ("usb" in navigator) && window.isSecureContext
      ? "This browser can attempt the browser-only receiver flow."
      : "This browser cannot use WebUSB here. Try Chromium on https:// or http://localhost."
  ].join("\n");
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;")
    .replaceAll("'", "&#39;");
}

function setBusy(busy) {
  startBtn.disabled = busy || receiverRunning;
  stopBtn.disabled = busy || !receiverRunning;
  ppmInput.disabled = busy || receiverRunning;
  sampleRateInput.disabled = busy || receiverRunning;
}

renderStatus("Idle", "");
describeSupport().catch(() => {
  supportOutput.textContent = "Browser support detection failed.";
});
