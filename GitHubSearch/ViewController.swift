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
extension URL {
    static func gitHubSearch(_ query: String, language: String) -> URL {
        let query = query.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)!
        return URL(string: "https://api.github.com/search/repositories?q=\(query)+language:\(language)+in:name")!
    }
}

/// Observable emitting the currently selected segment title
extension UISegmentedControl {
    public var rx_selectedTitle: Observable<String?> {
        return rx.value.map(titleForSegment)
    }
}

class ViewController: UIViewController {
    //MARK: - Outlets
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var query: UITextField!
    @IBOutlet weak var language: UISegmentedControl!
    
    
    //MARK: - Properties
    fileprivate let bag = DisposeBag()
    fileprivate var resultsBag = DisposeBag()

    fileprivate let realm = try! Realm()
    fileprivate var repos: Results<Repo>?

    //MARK: - Bind UI
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //define input
        let input = Observable.combineLatest(query.rx.text.filter { ($0?.utf8.count ?? 0) > 2}, language.rx_selectedTitle)
            {term, language in (term, language!)}
            .shareReplay(1)
        
        //call Github, save to Realm
        input.throttle(0.5, scheduler: MainScheduler.instance)
            .map { URL.gitHubSearch($0 ?? "", language: $1)}
            .do(onNext: { _ in UIApplication.shared.isNetworkActivityIndicatorVisible = true })
            .flatMapLatest { url in
                return URLSession.shared.rx.json(url: url).catchErrorJustReturn([])
            }
            .do(onNext: { _ in UIApplication.shared.isNetworkActivityIndicatorVisible = false })
            .observeOn(ConcurrentDispatchQueueScheduler(qos: DispatchQoS(qosClass: DispatchQoS.QoSClass.background, relativePriority: 1)))
            .map {json -> [Repo] in
                guard let json = json as? [String: AnyObject],
                    let items = json["items"] as? [AnyObject] else {return []}
                
                return items.map {Repo(value: $0)}
            }
            .subscribe(onNext: {repos in
                let realm = try! Realm()
                try! realm.write {
                    realm.add(repos, update: true)
                }
            })
            .addDisposableTo(bag)
        
        //bind results to table
        input.subscribe(onNext: {[weak self] in
                self?.bindTableView($0, language: $1)
            })
            .addDisposableTo(bag)
        
        //reset table
        query.rx.text.filter { ($0?.utf8.count ?? 0) <= 2}
            .subscribe(onNext: {[weak self] _ in
                self?.bindTableView(nil)
            })
            .addDisposableTo(bag)
    }
    
    /// bind results to table view
    func bindTableView(_ term: String?, language: String? = nil) {
        resultsBag = DisposeBag()

        guard let term = term, let language = language else {
            repos = nil
            tableView.reloadData()
            return
        }
        
        repos = realm.objects(Repo.self).filter("full_name CONTAINS[c] %@ AND language = %@", term, language)

        Observable.changeset(from: repos!)
            .subscribe(onNext: {[weak self] repos, changes in
                guard let tableView = self?.tableView else { return }
                
                if let changes = changes {
                    tableView.beginUpdates()
                    tableView.insertRows(at: changes.inserted.map { IndexPath(row: $0, section: 0) },
                                         with: .automatic)
                    tableView.endUpdates()
                } else {
                    tableView.reloadData()
                }
            })
            .addDisposableTo(resultsBag)
    }
}

extension ViewController: UITableViewDataSource {
    //MARK: - UITableView data source
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return repos?.count ?? 0
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let repo = repos![indexPath.row]
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "RepoCell")!
        cell.textLabel!.text = repo.full_name
        return cell
    }
}
