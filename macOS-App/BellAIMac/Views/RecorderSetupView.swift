import AppKit
import SwiftUI

// one stop of the walkthrough: what to do, and the commands for it, to copy into Terminal on this Mac
private struct Step: Identifiable {
    let id: String
    let title: String
    let detail: String
    var commands: [String] = []
}

// the wiring from Recorder/PINOUT.md: the board's label, the Pico W's GPIO, and its physical pin
private struct Wire: Identifiable {
    let label: String, gpio: String, pin: String
    var id: String { label }
}

private let sdWires = [
    Wire(label: "CLK", gpio: "GP18", pin: "24"), Wire(label: "MOSI", gpio: "GP19", pin: "25"),
    Wire(label: "MISO", gpio: "GP16", pin: "21"), Wire(label: "CS", gpio: "GP17", pin: "22"),
    Wire(label: "3V3", gpio: "3V3(OUT)", pin: "36"), Wire(label: "GND", gpio: "GND", pin: "23 (or any GND)"),
]

private let micWires = [
    Wire(label: "BCLK", gpio: "GP14", pin: "19"), Wire(label: "LRCL", gpio: "GP15", pin: "20"),
    Wire(label: "DOUT", gpio: "GP13", pin: "17"), Wire(label: "SEL", gpio: "GND (left channel)", pin: "18"),
    Wire(label: "3V", gpio: "3V3(OUT)", pin: "36"), Wire(label: "GND", gpio: "GND", pin: "18 (or any GND)"),
]

// walks through building, flashing and testing the clip-on recorder (Pico W), the same as Recorder/README.md
struct RecorderSetupView: View {
    @Environment(ServerController.self) private var servers
    @AppStorage("recorder.done") private var doneList = ""

    // the Recorder folder next to macserver in the checkout this app was built from
    private var recorder: String {
        let path = servers.folder?.deletingLastPathComponent().appendingPathComponent("Recorder").path ?? "~/BellAI/Recorder"
        return path.contains(" ") ? "'\(path)'" : path
    }

    private var steps: [Step] {
        [
            Step(id: "parts", title: "Gather the parts",
                 detail: "A Pico W, an ICS-43434 microphone board, a microSD module with a FAT32 card (32 GB or smaller), and a breadboard and wires. For battery use also a Pimoroni Pico LiPo SHIM and a protected LiPo. Wire it up in the next step."),
            Step(id: "wire", title: "Wire it up",
                 detail: "Use the tables below, wiring by each board's silkscreen label. Pin numbers count from the USB end, down the left side and up the right. LRCL must be the pin after BCLK. Never power the mic or SD module from 5 V."),
            Step(id: "toolchain", title: "Install the build tools",
                 detail: "Install ARM's arm-none-eabi toolchain from developer.arm.com, not Homebrew's, which has no C library and fails to build.",
                 commands: ["brew install cmake git"]),
            Step(id: "sdk", title: "Get the Pico SDK",
                 detail: "This puts it inside the Recorder folder.",
                 commands: ["cd \(recorder) && git clone --depth 1 --branch 2.1.1 https://github.com/raspberrypi/pico-sdk.git",
                            "cd \(recorder)/pico-sdk && git submodule update --init --depth 1 lib/cyw43-driver lib/lwip lib/tinyusb"]),
            Step(id: "config", title: "Write your settings",
                 detail: "Copy the example, then open config.h and set WIFI_SSID, WIFI_PASS and AUTH_TOKEN. For the first test set CHUNK_SECONDS to 60, so a file is one minute instead of an hour. config.h is not tracked by git, so your password stays here.",
                 commands: ["cd \(recorder) && cp config.example.h config.h && open -e config.h"]),
            Step(id: "build", title: "Build it",
                 detail: "This makes build/recorder.uf2.",
                 commands: ["cd \(recorder) && mkdir -p build && cd build && PICO_SDK_PATH=../pico-sdk cmake .. && make -j4"]),
            Step(id: "flash", title: "Flash it",
                 detail: "Hold the BOOTSEL button on the Pico W while plugging in the USB cable. A drive called RPI-RP2 appears. Copy the file onto it, and the Pico W restarts by itself.",
                 commands: ["cp \(recorder)/build/recorder.uf2 /Volumes/RPI-RP2/"]),
            Step(id: "receiver", title: "Start the receiver on this Mac",
                 detail: "The recorder finds it by scanning your Wi-Fi network for port 8080, so this Mac must be on the same network. Use the same AUTH_TOKEN as in config.h. Files arrive in a folder called received. If it can't be found, turn off client or AP isolation on your router, and avoid guest networks.",
                 commands: ["cd \(recorder) && AUTH_TOKEN=change-me python3 receiver.py 8080"]),
            Step(id: "serial", title: "Watch it work",
                 detail: "Open the log, talk near the microphone for 2 minutes, and expect it to connect, upload rec_000001.wav and print \"uploaded and deleted\". Press Control-A then K to quit, because the port stays busy while it is open and blocks flashing. If it repeats \"sd_init_medium: No disk\", check the SD wiring and the card.",
                 commands: ["screen /dev/tty.usbmodem* 115200"]),
            Step(id: "wifi", title: "Change the Wi-Fi from the phone",
                 detail: "Optional. For 15 seconds after power-up the recorder is visible over Bluetooth as \"BellAI Recorder\". In the iOS app, open Settings, Clip-on recorder, Recorder's Wi-Fi, enter the network and tap Send. Power-cycle it to reopen the window."),
            Step(id: "long", title: "Switch to hour-long files",
                 detail: "Only once the test works. Set CHUNK_SECONDS back to 3600 in config.h, rebuild, flash again, connect the battery and measure its current before relying on it.",
                 commands: ["cd \(recorder)/build && make -j4"]),
        ]
    }

    private var done: Set<String> { Set(doneList.split(separator: ",").map(String.init)) }

    var body: some View {
        let steps = steps
        let finished = steps.filter { done.contains($0.id) }.count
        Page("Recorder", subtitle: "\(finished) of \(steps.count) steps done") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Sets up the clip-on recorder: a Pico W that records to an SD card and uploads over Wi-Fi to this Mac or the iOS app. Commands run in Terminal on this Mac.")
                    .foregroundStyle(.secondary)
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    StepCard(number: index + 1, step: step, isDone: done.contains(step.id)) { toggle(step.id) }
                    if step.id == "wire" {
                        WiringCard(title: "SD card module (SPI0)", wires: sdWires, first: "SD board label")
                        WiringCard(title: "ICS-43434 mic (I2S)", wires: micWires, first: "Mic label")
                    }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        var now = done
        if !now.insert(id).inserted { now.remove(id) }
        doneList = now.sorted().joined(separator: ",")
    }
}

private struct StepCard: View {
    let number: Int
    let step: Step
    let isDone: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isDone ? Theme.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "Mark step \(number) not done" : "Mark step \(number) done")
            VStack(alignment: .leading, spacing: 8) {
                Text("\(number). \(step.title)").font(.system(size: 15, weight: .semibold))
                Text(step.detail).font(.system(size: 13)).foregroundStyle(.secondary)
                ForEach(step.commands, id: \.self) { CommandLine(command: $0) }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .panel()
        .opacity(isDone ? 0.6 : 1)
    }
}

private struct WiringCard: View {
    let title: String
    let wires: [Wire]
    let first: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            GridRow {
                Text(title).font(.system(size: 13, weight: .semibold)).gridCellColumns(3)
            }
            GridRow {
                Text(first).foregroundStyle(.secondary)
                Text("Pico GPIO").foregroundStyle(.secondary)
                Text("Physical pin").foregroundStyle(.secondary)
            }
            Divider().gridCellColumns(3)
            ForEach(wires) { wire in
                GridRow {
                    Text(wire.label).font(.system(size: 12, design: .monospaced))
                    Text(wire.gpio)
                    Text(wire.pin)
                }
            }
        }
        .font(.system(size: 13))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}

private struct CommandLine: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy command")
            .accessibilityLabel("Copy command")
        }
        .padding(10)
        .background(Theme.code, in: RoundedRectangle(cornerRadius: 8))
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
