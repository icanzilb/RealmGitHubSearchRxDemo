//
//  ViewController.swift
//  GitHubSearch
//
//  Created by Marin Todorov on 5/11/16.
//  Copyright © 2016 Realm Inc. All rights reserved.
//

// For brevity all the example code is included in this single file,
// in your own projects you should spread code and logic into different classes.

import UIKit

import RxSwift
import RxCocoa

import RealmSwift
import RxRealm

/// provide factory method for urls to GitHub's search API
extension NSURL {
    static func gitHubSearch(query: String, language: String) -> NSURL {
        let query = query.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLQueryAllowedCharacterSet())!
        return NSURL(string: "https://api.github.com/search/repositories?q=\(query)+language:\(language)+in:name")!
    }
}

/// Observable emitting the currently selected segment title
extension UISegmentedControl {
    public var rx_selectedTitle: Observable<String?> {
        return rx_value.map(titleForSegmentAtIndex)
    }
}

class ViewController: UIViewController {
    //MARK: - Outlets
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var query: UITextField!
    @IBOutlet weak var language: UISegmentedControl!
    
    
    //MARK: - Properties
    private let bag = DisposeBag()
    private var resultsBag = DisposeBag()

    private let realm = try! Realm()
    private var repos: Results<Repo>?

    //MARK: - Bind UI
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //define input
        let input = Observable.combineLatest(query.rx_text.filter {$0.utf8.count > 2}, language.rx_selectedTitle)
            {term, language in (term, language!)}
            .shareReplay(1)
        
        //call Github, save to Realm
        input.throttle(0.5, scheduler: MainScheduler.instance)
            .map(NSURL.gitHubSearch)
            .doOnNext { _ in UIApplication.sharedApplication().networkActivityIndicatorVisible = true }
            .flatMapLatest { url in
                return NSURLSession.sharedSession().rx_JSON(url).catchErrorJustReturn([])
            }
            .doOnNext { _ in UIApplication.sharedApplication().networkActivityIndicatorVisible = false }
            .observeOn(ConcurrentDispatchQueueScheduler(globalConcurrentQueueQOS: .Background))
            .map {json -> [Repo] in
                guard let json = json as? [String: AnyObject],
                    items = json["items"] as? [AnyObject] else {return []}
                
                return items.map {Repo(value: $0)}
            }
            .subscribeNext {repos in
                let realm = try! Realm()
                try! realm.write {
                    realm.add(repos, update: true)
                }
            }
            .addDisposableTo(bag)
        
        //bind results to table
        input
            .subscribeNext {[weak self] in
                self?.bindTableView($0, language: $1)
            }
            .addDisposableTo(bag)
        
        //reset table
        query.rx_text.filter {$0.utf8.count <= 2}
            .subscribeNext {[weak self] _ in
                self?.bindTableView(nil)
            }
            .addDisposableTo(bag)
    }
    
    /// bind results to table view
    func bindTableView(term: String?, language: String? = nil) {
        resultsBag = DisposeBag()

        guard let term = term, let language = language else {
            repos = nil
            tableView.reloadData()
            return
        }
        
        repos = realm.objects(Repo).filter("full_name CONTAINS[c] %@ AND language = %@", term, language)
        repos!.asObservableChangeset()
            .subscribeNext {[weak self] repos, changes in
                guard let tableView = self?.tableView else { return }
                
                if let changes = changes {
                    tableView.beginUpdates()
                    tableView.insertRowsAtIndexPaths(changes.inserted.map { NSIndexPath(forRow: $0, inSection: 0) },
                        withRowAnimation: .Automatic)
                    tableView.endUpdates()
                } else {
                    tableView.reloadData()
                }
            }
            .addDisposableTo(resultsBag)
    }
}

extension ViewController: UITableViewDataSource {
    //MARK: - UITableView data source
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return repos?.count ?? 0
    }
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let repo = repos![indexPath.row]
        
        let cell = tableView.dequeueReusableCellWithIdentifier("RepoCell")!
        cell.textLabel!.text = repo.full_name
        return cell
    }
}