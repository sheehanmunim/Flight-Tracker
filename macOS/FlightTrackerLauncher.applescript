property appName : "Flight Tracker"

on run
    set configPath to ensureConfigFile()
    set dashboardUrl to readDashboardUrl(configPath)

    if dashboardUrl is "" then
        return
    end if

    open location dashboardUrl
end run

on ensureConfigFile()
    set supportRoot to POSIX path of (path to home folder) & "Library/Application Support/" & appName
    set configPath to supportRoot & "/flight-tracker-url.txt"

    do shell script "mkdir -p " & quoted form of supportRoot

    if not fileExists(configPath) then
        try
            set bundledDefault to POSIX path of (path to resource "default-flight-tracker-url.txt")
            do shell script "cp " & quoted form of bundledDefault & " " & quoted form of configPath
        on error
            do shell script "printf %s " & quoted form of "http://YOUR-WINDOWS-HOST:5099/?key=REPLACE_ME\n" & " > " & quoted form of configPath
        end try
    end if

    return configPath
end ensureConfigFile

on readDashboardUrl(configPath)
    set dashboardUrl to do shell script "head -n 1 " & quoted form of configPath & " | tr -d '\\r'"

    if dashboardUrl is "" or dashboardUrl contains "REPLACE_ME" then
        tell application "TextEdit"
            activate
            open POSIX file configPath
        end tell

        display dialog "Edit flight-tracker-url.txt with the shared dashboard URL from your Windows host, then open Flight Tracker again." buttons {"OK"} default button "OK" with title appName
        return ""
    end if

    return dashboardUrl
end readDashboardUrl

on fileExists(posixPath)
    try
        do shell script "test -f " & quoted form of posixPath
        return true
    on error
        return false
    end try
end fileExists
