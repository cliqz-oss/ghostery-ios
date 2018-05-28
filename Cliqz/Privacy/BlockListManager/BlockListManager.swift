//
//  GhosteryBlockListHelper.swift
//  BrowserCore
//
//  Created by Tim Palade on 3/19/18.
//  Copyright © 2018 Tim Palade. All rights reserved.
//

import WebKit

final class BlockListManager {
    
    static let shared = BlockListManager()
    
    fileprivate let loadQueue: OperationQueue = OperationQueue()
    
    init() {
        loadQueue.maxConcurrentOperationCount = 1
        loadQueue.qualityOfService = .utility
        
    }
    
    func getBlockLists(forIdentifiers: [String], callback: @escaping ([WKContentRuleList]) -> Void) {
        
        var returnList = [WKContentRuleList]()
        let dispatchGroup = DispatchGroup()
        let listStore = WKContentRuleListStore.default()
        var blfm: BlockListFileManager? = nil
        
        for id in forIdentifiers {
            dispatchGroup.enter()
            listStore?.lookUpContentRuleList(forIdentifier: id) { (ruleList, error) in
                if let ruleList = ruleList {
                    returnList.append(ruleList)
                    dispatchGroup.leave()
                }
                else {
                    debugPrint("CACHE: did not find list for identifier = \(id)")
                    if blfm == nil {
                        blfm = BlockListFileManager()
                    }
                    if let json = blfm!.json(forIdentifier: id) {
                        debugPrint("CACHE: will compile list for identifier = \(id)")
                        let operation = CompileOperation(identifier: id, json: json)
                        
                        operation.completionBlock = {
                            if let list = self.handleOperationResult(result: operation.result, id: id) {
                                returnList.append(list)
                            }
                            dispatchGroup.leave()
                        }
                        
                        self.loadQueue.addOperation(operation)
                    }
                    else {
                        dispatchGroup.leave()
                    }
                }
            }
        }
        
        dispatchGroup.notify(queue: .global()) {
            callback(returnList)
        }
    }
    
    private func handleOperationResult(result: CompileOperation.Result, id: String) -> WKContentRuleList? {
        switch result {
        case .list(let list):
            debugPrint("finished loading list for id = \(id)")
            return list
        case .error(let error):
            debugPrint("error for id = \(id) | ERROR = \(error.debugDescription)")
            return nil
        case .noResult:
            debugPrint("no result for id = \(id)")
            return nil
        }
    }
}
