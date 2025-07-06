import Network

final class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var wasOnline = true
    @Published private(set) var isOnline = true
    
    var onStatusChange: (Bool) -> Void = { _ in }
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            
            let isOnlineNow = (path.status == .satisfied)
            
            self.isOnline = isOnlineNow
            
            if wasOnline != isOnlineNow {
                onStatusChange(isOnlineNow)
            }
            
            wasOnline = isOnlineNow
            
        }
        monitor.start(queue: queue)
    }
}
