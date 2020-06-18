import Foundation

public protocol DownloadingServicesDelegate: class {
    func downloadingServices(_ services: DownloadingServices, didChangeStatus: DownloadingServicesStatus)
    func downloadingServices(_ services: DownloadingServices, didFinishWithError: Error?)
    func downloadingServices(_ services: DownloadingServices, didReviceData: Data, progress: Float)
}


public enum DownloadingServicesStatus: String {
    case unstart
    case start
    case pause
    case stop
    case finish
    case canceled
    case failed
}

public protocol DownloadingServices: AnyObject {
    var delegate: DownloadingServicesDelegate? { get set }
    var url: URL? { get set }
    var status: DownloadingServicesStatus { get }
    var progress: Float { get }
    var useCache: Bool { get set }
    
    func start()
    func pause()
    func stop()
}
