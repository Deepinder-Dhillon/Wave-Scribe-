import Network

final class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    @Published private(set) var isOnline = true
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if(path.status == .satisfied){
                isOnline = true }
            else {
                isOnline = false
            }
            
        }
        monitor.start(queue: queue)
    }
}
