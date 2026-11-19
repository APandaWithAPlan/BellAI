import CoreBluetooth
import Foundation
import Observation

// sets the Wi-Fi network the Pico recorder uploads through, over Bluetooth LE (firmware: bellaimic/provision.c).
// the recorder only listens for a few minutes after power-up. the message is
//     [len][recorder password] [len][network name] [len][network password]     each len one byte
// a wrong recorder password is refused by the recorder. the Bluetooth link isn't encrypted, so the network password is
// readable by anyone sniffing it during the second it takes to send

nonisolated enum RecorderSetupError: LocalizedError, Equatable {
    case noName, nameTooLong, passwordLength, lineBreak, tokenTooLong
    case bluetoothOff, bluetoothDenied, notFound, lostConnection, tooFar, wrongToken, refused

    var errorDescription: String? {
        switch self {
        case .noName: "Enter the Wi-Fi network name."
        case .nameTooLong: "A Wi-Fi name can be at most 32 bytes."
        case .passwordLength: "A Wi-Fi password is 8 to 63 characters, or empty for an open network."
        case .lineBreak: "The name and password can't contain a line break."
        case .tokenTooLong: "The recorder password is too long."
        case .bluetoothOff: "Turn Bluetooth on and try again."
        case .bluetoothDenied: "Allow Bluetooth for BellAI in Settings and try again."
        case .notFound: "Couldn't find the recorder. It only listens for 15 seconds after power-up, so tap Send first, then unplug it and plug it in again."
        case .lostConnection: "Lost the connection to the recorder. Try again closer to it."
        case .tooFar: "The Bluetooth link is too slow for this message. Move closer and try again."
        case .wrongToken: "The recorder refused the password. It must match AUTH_TOKEN in the recorder's config.h."
        case .refused: "The recorder refused the Wi-Fi settings."
        }
    }
}

nonisolated enum RecorderSetupMessage {
    static let service = CBUUID(string: "6F1A0001-7B3C-4E8A-9D52-0C3E1B7A4F10")
    static let characteristic = CBUUID(string: "6F1A0002-7B3C-4E8A-9D52-0C3E1B7A4F10")

    static func encode(token: String, ssid: String, password: String) throws -> Data {
        let fields = [Data(token.utf8), Data(ssid.utf8), Data(password.utf8)]
        guard fields[1].count > 0 else { throw RecorderSetupError.noName }
        guard fields[1].count <= 32 else { throw RecorderSetupError.nameTooLong }
        guard fields[0].count <= 255 else { throw RecorderSetupError.tokenTooLong }
        guard fields[2].isEmpty || (8...63).contains(fields[2].count) else { throw RecorderSetupError.passwordLength }
        // the recorder keeps these in a one-line-per-value file
        guard !fields[1...].contains(where: { $0.contains(10) || $0.contains(13) || $0.contains(0) }) else { throw RecorderSetupError.lineBreak }
        return fields.reduce(into: Data()) { message, field in
            message.append(UInt8(field.count))
            message.append(field)
        }
    }
}

@MainActor
@Observable
final class RecorderWifiSetup: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    enum Phase: Equatable {
        case idle
        case searching
        case connecting
        case sending
        case done
        case failed(RecorderSetupError)
    }

    private(set) var phase = Phase.idle
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var message: Data?
    private var timeout: Task<Void, Never>?

    var isBusy: Bool {
        switch phase {
        case .searching, .connecting, .sending: true
        case .idle, .done, .failed: false
        }
    }

    // finds the recorder and gives it the network. progress and the result show in `phase`
    func send(token: String, ssid: String, password: String) {
        guard !isBusy else { return }
        do {
            message = try RecorderSetupMessage.encode(token: token.trimmingCharacters(in: .whitespacesAndNewlines), ssid: ssid, password: password)
        } catch {
            return fail(error as? RecorderSetupError ?? .refused)
        }
        phase = .searching
        // the first use asks for the Bluetooth permission, and then reports the state
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else { startScan() }
        arm(.notFound, after: 30)
    }

    func cancel() {
        finish(.idle)
    }

    private func startScan() {
        guard let central else { return }
        switch central.state {
        case .poweredOn: central.scanForPeripherals(withServices: [RecorderSetupMessage.service])
        case .unauthorized: fail(.bluetoothDenied)
        case .unknown, .resetting: break   // the state callback follows
        default: fail(.bluetoothOff)
        }
    }

    private func arm(_ error: RecorderSetupError, after seconds: Double) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { self?.fail(error) }
        }
    }

    private func fail(_ error: RecorderSetupError) { finish(.failed(error)) }

    private func finish(_ result: Phase) {
        timeout?.cancel()
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        message = nil
        phase = result
    }

    // MARK: CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if phase == .searching { startScan() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard phase == .searching else { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        phase = .connecting
        arm(.lostConnection, after: 15)
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([RecorderSetupMessage.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if isBusy { fail(.lostConnection) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if isBusy { fail(.lostConnection) }
    }

    // MARK: CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == RecorderSetupMessage.service }) else { return fail(.lostConnection) }
        peripheral.discoverCharacteristics([RecorderSetupMessage.characteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == RecorderSetupMessage.characteristic }),
              let message else { return fail(.lostConnection) }
        // the recorder takes the message in one write, not a long write. what fits in one write is the
        // withoutResponse size; withResponse would report 512 and iOS would split it up
        guard peripheral.maximumWriteValueLength(for: .withoutResponse) >= message.count else { return fail(.tooFar) }
        phase = .sending
        arm(.lostConnection, after: 10)
        peripheral.writeValue(message, for: characteristic, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard phase == .sending else { return }
        guard let error else { return finish(.done) }
        // 0x80 is the recorder's own "wrong password" code. it avoids the standard authorization codes, which make iOS try to pair
        let attError = error as NSError
        fail(attError.domain == CBATTErrorDomain && attError.code == 0x80 ? .wrongToken : .refused)
    }
}
