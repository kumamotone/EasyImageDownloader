//
//  ContentView.swift
//  EasyDownloader
//
//  Created by Kumamoto on 2019/07/12.
//  Copyright © 2019 Kumamoto. All rights reserved.
//

import Combine
import SwiftUI

extension Int {
    /**
     Return a String.
     ex: 001, 0123
     parameter digits: the number of digits
     */
    func toStr(digits: Int) -> String {
        return String(format: "%0\(digits)d", self)
    }
}

extension String {
    /**
     Return a Int value from String.
     If failed, return 0.
     */
    func toInt() -> Int {
        if let int = Int(self) {
            return int
        } else {
            return 0
        }
    }
}

/**
 Generate default folder name from Date().
 ex: /Picture/20190712_235801
 */
func defaultFolderName() -> String {
    let now = Date()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    return "/Picture/\(formatter.string(from: now))"
}

enum MyError: Error {
    case parseURL
    case generateURL
    case mkdir
    case fileSave
}

final class AnySubscription: Subscription {
    private let cancellable: Cancellable
    
    init(_ cancel: @escaping () -> Void) {
        cancellable = AnyCancellable(cancel)
    }
    
    func request(_ demand: Subscribers.Demand) {}
    
    func cancel() {
        cancellable.cancel()
    }
}

struct RequestPublisher: Publisher {
    typealias Output = String
    typealias Failure = MyError
    
    let allNums: [Int]
    let digits: Int
    let ext: String

    let downloadURL: String
    let saveDirectoryPath: String
    
    func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {

        guard let url = URL(string: self.downloadURL) else {
            subscriber.receive(completion: .failure(.parseURL))
            return
        }
        
        if !FileManager.default.fileExists(atPath: self.saveDirectoryPath) {
            do {
                try FileManager.default.createDirectory(atPath: self.saveDirectoryPath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                subscriber.receive(completion: .failure(.mkdir))
            }
        }

        let session = URLSession(configuration: URLSessionConfiguration.default)
    
        for num in allNums {
            let URLwithOutFileName = url.deletingLastPathComponent().description
            let fileName = num.toStr(digits: self.digits) + "." + self.ext
            
            guard let targetURL = URL(string: URLwithOutFileName + fileName) else {
                _ = subscriber.receive("\(fileName) is not found. skipping..")

                continue
            }
            
            let task = session.dataTask(with: targetURL) { data, response, error in
                do {
                    try data?.write(to: URL(fileURLWithPath: self.saveDirectoryPath + "/" + fileName))
                    _ = subscriber.receive("downloaded: \(targetURL.description)")
                } catch {
                    subscriber.receive(completion: .failure(.fileSave))
                }
            }
            task.resume()
        }
        
    }
}

class Requester: BindableObject {
    
    private var cancellable: Cancellable?
    let willChange = PassthroughSubject<Requester, Never>()
    var logStrings: [String] = [] {
        didSet {
            DispatchQueue.main.async { // Because receiveOn don't work
                self.willChange.send(self)
            }
        }
    }
    
    deinit {
        print("deinited")
    }
    
    func request(allNums: [Int], digits: Int, ext: String, url: String, path: String) {
            cancellable = RequestPublisher(allNums: allNums,
                     digits: digits,
                     ext: ext,
                     downloadURL: url,
                     saveDirectoryPath: path)
                .eraseToAnyPublisher()
//                .subscribe(on: concurrentQueue)
//                .receive(on: RunLoop.main)
//                .debounce(for: .milliseconds(1_000), scheduler: RunLoop.main)
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        print("finished")
                    case .failure(let error):
                        print("error:\(error.localizedDescription)")
                    }
                }, receiveValue: { string in
                    self.logStrings.append(string)
                    print("\(string)")
                })
    }
    
    func cancel() {
        cancellable?.cancel()
    }
}

struct ContentView : View {
    @State var url: String = "https://www.bikaken.or.jp/research/group/shibasaki/shibasaki-lab/lab-info/gallery/sympo19th/images/001.jpg" // ex. https://www.bikaken.or.jp/research/group/shibasaki/shibasaki-lab/lab-info/gallery/sympo19th/images/001.jpg
    @State var startNum: String = "001"
    @State var endNum: String = "010"
    @State var ext: String = "jpg"
    @State var digits: String = "3"
    @State var path: String = NSHomeDirectory() + defaultFolderName()
    
    @State var requester = Requester()
    
    var body: some View {
        VStack {
            Text("Image Downloader")
            HStack {
                Text("URL")
                TextField("URL", text: $url)
                Text("ex. https://domain.com/imgpath/001.jpg")
            }
            HStack {
                Text("start")
                TextField("start", text: $startNum)
            }
            HStack {
                Text("end")
                TextField("end", text: $endNum)
            }
            HStack {
                Text("ext")
                TextField("ext", text: $ext)
            }
            HStack {
                Text("digits")
                TextField("digits", text: $digits)
                Text("ex. 001 -> 3, 0001 -> 4")
            }
            HStack {
                Text("Path")
                TextField("Path", text: $path)
                Button("Open Finder") {
                    let openPanel = NSOpenPanel()
                    openPanel.allowsMultipleSelection = false   // 複数ファイルの選択
                    openPanel.canChooseDirectories    = true    // ディレクトリの選択
                    openPanel.canCreateDirectories    = true    // ディレクトリの作成
                    openPanel.canChooseFiles          = false   // ファイルの選択
                    // openPanel.allowedFileTypes        = []   // ファイルの種類

                    
                    let reault = openPanel.runModal()
                    if (reault == .OK) {
                        if let url = openPanel.url {
                            self.path = url.path
                        }
                    }
                }
                Button("Default") {
                    self.path = NSHomeDirectory() + defaultFolderName()
                }
            }
            HStack {
                Button("run") {
                    let allNums = [Int](self.startNum.toInt()...self.endNum.toInt()) // cast
                    self.requester.request(allNums: allNums,
                                      digits: self.digits.toInt(),
                                      ext: self.ext,
                                      url: self.url,
                                      path: self.path)
                }
                Button("cancel") {
                    self.requester.cancel()
                }
            }
            List(requester.logStrings.identified(by: \.self)) {
                Text("\($0)")
            }
        }.frame(width: 1024, height: 500)
    }
}


#if DEBUG
struct ContentView_Previews : PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
