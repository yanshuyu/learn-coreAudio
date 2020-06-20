import Foundation

public protocol DownloadingServicesDelegate: class {
    func downloadingServices(_ services: DownloadingServices, didChangeStatus: DownloadingStatus)
    func downloadingServices(_ services: DownloadingServices, didFinishWithError: Error?)
    func downloadingServices(_ services: DownloadingServices, didReviceData: Data, progress: Float)
}


public enum DownloadingStatus: String {
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
    var status: DownloadingStatus { get }
    var progress: Float { get }
    var useCache: Bool { get set }
    
    func start()
    func pause()
    func stop()
}
