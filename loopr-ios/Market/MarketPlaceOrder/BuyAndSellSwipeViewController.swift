//
//  BuyViewController.swift
//  loopr-ios
//
//  Created by xiaoruby on 3/10/18.
//  Copyright © 2018 Loopring. All rights reserved.
//

import UIKit

class BuyAndSellSwipeViewController: SwipeViewController {
    
    var market: Market!

    var initialType: TradeType = .buy
    var initialPrice: String?
    
    private var types: [TradeType] = [.buy, .sell]
    private var viewControllers: [UIViewController] = []
    var options = SwipeViewOptions.getDefault()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        setBackButton()
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false

        self.view.theme_backgroundColor = ColorPicker.backgroundColor
        self.navigationItem.title = PlaceOrderDataManager.shared.market.description

        let vc1 = BuyViewController(type: .buy)
        vc1.market = market

        let vc2 = BuyViewController(type: .sell)
        vc2.market = market
        
        vc1.initialPrice = initialPrice
        vc2.initialPrice = initialPrice
        
        var initIndex = initialType == .buy ? 0 : 1
        
        if !tokenBuyBalanceIsZero() {
            viewControllers.append(vc1)
        } else {
            initIndex = 0
            types = [.sell]
        }
        
        if !tokenSellBalanceIsZero() {
            viewControllers.append(vc2)
        } else {
            initIndex = 0
            types = [.buy]
        }
        
        for viewController in viewControllers {
            self.addChildViewController(viewController)
        }

        if Themes.isDark() {
            options.swipeTabView.itemView.textColor = UIColor(rgba: "#ffffff66")
            options.swipeTabView.itemView.selectedTextColor = UIColor(rgba: "#ffffffcc")
        } else {
            options.swipeTabView.itemView.textColor = UIColor(rgba: "#00000099")
            options.swipeTabView.itemView.selectedTextColor = UIColor(rgba: "#000000cc")
        }
        swipeView.reloadData(options: options, default: initIndex)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    // To avoid gesture conflicts in swiping to back and UISlider
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view != nil && touch.view!.isKind(of: UIControl.self) {
            return false
        }
        return true
    }

    // MARK: - Delegate
    override func swipeView(_ swipeView: SwipeView, viewWillSetupAt currentIndex: Int) {
        // print("will setup SwipeView")
    }
    
    override func swipeView(_ swipeView: SwipeView, viewDidSetupAt currentIndex: Int) {
        // print("did setup SwipeView")
    }
    
    override func swipeView(_ swipeView: SwipeView, willChangeIndexFrom fromIndex: Int, to toIndex: Int) {
        // print("will change from item \(fromIndex) to item \(toIndex)")
    }
    
    override func swipeView(_ swipeView: SwipeView, didChangeIndexFrom fromIndex: Int, to toIndex: Int) {
        // print("did change from item \(fromIndex) to section \(toIndex)")
    }
    
    // MARK: - DataSource
    override func numberOfPages(in swipeView: SwipeView) -> Int {
        return viewControllers.count
    }
    
    override func swipeView(_ swipeView: SwipeView, titleForPageAt index: Int) -> String {
        return types[index].description
    }
    
    override func swipeView(_ swipeView: SwipeView, viewControllerForPageAt index: Int) -> UIViewController {
        return viewControllers[index]
    }
    
    func tokenSellBalanceIsZero() -> Bool {
        let tokenS = PlaceOrderDataManager.shared.tokenA.symbol
        if let asset = CurrentAppWalletDataManager.shared.getAsset(symbol: tokenS) {
            return asset.balance == 0 ? true : false
        } else {
            return false
        }
    }
    
    func tokenBuyBalanceIsZero() -> Bool {
        let tokenB = PlaceOrderDataManager.shared.tokenB.symbol
        if let asset = CurrentAppWalletDataManager.shared.getAsset(symbol: tokenB) {
            return asset.balance == 0 ? true : false
        } else {
            return false
        }
    }
}
