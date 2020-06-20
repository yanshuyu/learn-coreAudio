
import Foundation
import os.log

public class StreamDownloadServices: NSObject, DownloadingServices {
    fileprivate var logger = OSLog(subsystem: "com.audioStreamEngine.sy", category: "downloading")
    public var delegate: DownloadingServicesDelegate?
    
    public var url: URL? = nil {
        didSet {
            reset()
        }
    }
    
    public var status: DownloadingStatus = .unstart {
        didSet {
            os_log(.debug, log: self.logger, "download status did change to: %@", self.status.rawValue)
            self.delegate?.downloadingServices(self, didChangeStatus: self.status)
        }
    }
    
    public private(set) var progress: Float = 0
    
    public var useCache: Bool = true {
        didSet {
            os_log(.debug, log: self.logger, "use cache: %i", self.useCache)
            self.urlSession.configuration.urlCache = self.useCache ? URLCache.shared : nil
            self.urlSession.configuration.requestCachePolicy = self.useCache ? .useProtocolCachePolicy : .reloadIgnoringLocalCacheData
        }
    }
    
    fileprivate lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    fileprivate var dataTask: URLSessionDataTask?
    
    public private(set) var totalBytesReviced: Int64 = 0
    public private(set) var totalBytesCount: Int64 = 0
    
    public func start() {
        guard let _ = self.url else { return }
        
        if self.dataTask == nil {
            self.dataTask = self.urlSession.dataTask(with: self.url!)
        }
        
        switch self.status {
            case .start, .finish, .failed:
                return
            default:
                self.status = .start
                self.dataTask?.resume()
        }
    }
    
    public func pause() {
        guard let task = self.dataTask,
            self.status == .start else {
                return
        }
        self.status = .pause
        task.suspend()
    }
    
    public func stop() {
        guard let task = self.dataTask,
            self.status == .start || self.status == .pause else {
                return
        }
        self.status = .stop
        task.cancel()
    }
    
    fileprivate func reset() {
        if self.status == .start {
            self.dataTask?.cancel()
            self.status = .canceled
        }
        self.status = .unstart
        self.progress = 0
        self.dataTask = nil
        self.totalBytesCount = 0
        self.totalBytesReviced = 0
    }
    

}

extension StreamDownloadServices: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if self.dataTask?.originalRequest == dataTask.originalRequest {
            self.totalBytesCount = response.expectedContentLength
            completionHandler(.allow)
        } else {
            completionHandler(.cancel)
        }
    }
    
    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           didReceive data: Data) {
        guard self.dataTask?.originalRequest == dataTask.originalRequest else {
            return
        }
        self.totalBytesReviced += Int64(data.count)
        self.progress = Float(Float64(self.totalBytesReviced) / Float64(self.totalBytesCount))
        self.delegate?.downloadingServices(self, didReviceData: data, progress: self.progress)
        os_log(.debug, log: self.logger,"did revice %i bytes of %i total bytes, progress: %f", self.totalBytesReviced, self.totalBytesCount, self.progress)
    }
    
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didCompleteWithError error: Error?) {
        guard self.dataTask?.originalRequest == dataTask?.originalRequest else {
            return
        }
        
        if let urlError = error as NSError? {
            if urlError.domain == NSURLErrorDomain && urlError.code == NSURLErrorCancelled {
                os_log(.debug, log: self.logger,"did cancel downloading url: %@",  task.originalRequest?.url?.absoluteString ?? "nil")
                return
            }
        }
        
        self.status = error == nil ? .finish : .failed
        self.delegate?.downloadingServices(self, didFinishWithError: error)
        let url = task.originalRequest?.url?.absoluteString ?? "nil"
        os_log(.debug, log: self.logger,"did finish downloading url: %@, error: %@", url, error.debugDescription)
    }
}


