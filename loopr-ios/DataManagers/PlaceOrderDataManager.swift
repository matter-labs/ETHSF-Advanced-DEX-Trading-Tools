//
//  PlaceOrderDataManager.swift
//  loopr-ios
//
//  Created by xiaoruby on 3/10/18.
//  Copyright © 2018 Loopring. All rights reserved.
//

import Foundation
import Geth

class PlaceOrderDataManager {
    
    static let shared = PlaceOrderDataManager()
    
    private var marginSplit: Double
    private var lrcFeeInSetting: Double
    private var userInfo: [String: Any] = [:]
    
    private let gasManager = GasDataManager.shared
    private let tokenManager = TokenDataManager.shared
    private let walletManager = CurrentAppWalletDataManager.shared
    private let sendManager = SendCurrentAppWalletDataManager.shared
    
    // Similar naming in Trade.swift
    var tokenA: Token!
    var tokenB: Token!
    var market: Market!

    private init() {
        self.marginSplit = SettingDataManager.shared.getMarginSplit()
        self.lrcFeeInSetting = SettingDataManager.shared.getLrcFeeRatio()
    }

    func new(tokenA: String, tokenB: String, market: Market) {
        self.tokenA = TokenDataManager.shared.getTokenBySymbol(tokenA)!
        self.tokenB = TokenDataManager.shared.getTokenBySymbol(tokenB)!
        self.market = market
    }

    func complete() -> Bool {
        return true
    }
    
    func getFrozenLRCFeeFromServer() -> Double {
        var result: Double = 0
        let semaphore = DispatchSemaphore(value: 0)
        if let address = walletManager.getCurrentAppWallet()?.address {
            LoopringAPIRequest.getFrozenLRCFee(owner: address, completionHandler: { (data, error) in
                guard error == nil, let lrc = data else {
                    return
                }
                result = lrc
                semaphore.signal()
            })
        }
        _ = semaphore.wait(timeout: .distantFuture)
        return result
    }
    
    func getEstimatedAllocatedAllowanceFromServer(token: String) -> Double {
        var result: Double = 0
        let semaphore = DispatchSemaphore(value: 0)
        if let address = walletManager.getCurrentAppWallet()?.address {
            LoopringAPIRequest.getEstimatedAllocatedAllowance(owner: address, token: token, completionHandler: { (data, error) in
                guard error == nil, let allowance = data else {
                    return
                }
                result = allowance
                semaphore.signal()
            })
        }
        _ = semaphore.wait(timeout: .distantFuture)
        return result
    }
    
    func approve(token: String, amount: Int64, completion: @escaping (String?, Error?) -> Void) {
        if let to = TokenDataManager.shared.getContractAddressBySymbol(symbol: token) {
            var error: NSError? = nil
            let approve = GethNewBigInt(amount)!
            let gas = GethBigInt.generateBigInt(gasManager.getGasPrice())!
            let contractAddress = GethNewAddressFromHex(RelayAPIConfiguration.delegateAddress, &error)!
            let toaddress = GethNewAddressFromHex(to, &error)!
            sendManager._approve(contractAddress: contractAddress, toAddress: toaddress, tokenAmount: approve, gasPrice: gas, completion: completion)
        } else {
            userInfo["message"] = NSLocalizedString("approving token contract address not found", comment: "")
            let error = NSError(domain: "approve", code: 0, userInfo: userInfo)
            completion(nil, error)
        }
    }
    
    func isLRCEnough(to amounts: Double, completion: @escaping (String?, Error?) -> Void) -> Bool {
        var result = false
        let lrcFrozen = getFrozenLRCFeeFromServer()
        let lrcBlance = walletManager.getBalance(of: "LRC")!
        result = lrcBlance > self.lrcFeeInSetting * amounts + lrcFrozen
        if !result {
            userInfo["message"] = NSLocalizedString("LRC balance in current wallet not enough for paying LRC FEE", comment: "")
            let error = NSError(domain: "validate", code: 0, userInfo: userInfo)
            completion(nil, error)
        }
        return result
    }
    
    func isGasEnough(for token: String, to amountSell: Double, includingLRC: Bool = true, completion: @escaping (String?, Error?) -> Void) -> Bool {
        var result = false
        if let ethBalance = walletManager.getBalance(of: "ETH"),
            let tokenGas = calculateGas(for: token, to: amountSell, completion: completion) {
            if includingLRC {
                if let lrcGas = calculateGas(for: "LRC", to: amountSell, completion: completion) {
                    result = ethBalance >= lrcGas + tokenGas
                }
            } else {
                result = ethBalance >= tokenGas
            }
        }
        if !result {
            userInfo["message"] = NSLocalizedString("ETH balance in current wallet not enough for paying gas for approving token", comment: "")
            let error = NSError(domain: "validate", code: 0, userInfo: userInfo)
            completion(nil, error)
        }
        return result
    }
    
    func isLRCGasEnough(to amountSell: Double, completion: @escaping (String?, Error?) -> Void) -> Bool {
        var result = false
        if let ethBalance = walletManager.getBalance(of: "ETH"), let lrcGas = calculateGasForLRC(to: amountSell, completion: completion) {
            result = ethBalance >= lrcGas
        }
        if !result {
            userInfo["message"] = NSLocalizedString("ETH balance in current wallet not enough for paying gas for approving LRC", comment: "")
            let error = NSError(domain: "validate", code: 0, userInfo: userInfo)
            completion(nil, error)
        }
        return result
    }
    
    func calculateGas(for token: String, to amountSell: Double, completion: @escaping (String?, Error?) -> Void) -> Double? {
        var result: Double? = nil
        if let asset = walletManager.getAsset(symbol: token) {
            if token.uppercased() == "LRC" {
                let lrcFrozen = getFrozenLRCFeeFromServer()
                if asset.allowance >= amountSell * self.lrcFeeInSetting + lrcFrozen {
                    return 0
                }
            } else {
                let tokenFrozen = getEstimatedAllocatedAllowanceFromServer(token: token)
                if asset.allowance >= amountSell + tokenFrozen {
                    return 0
                }
            }
            let gasAmount = gasManager.getGasAmount(by: "approve")
            if asset.allowance == 0 {
                result = gasAmount
            } else {
                result = gasAmount * 2
                approve(token: token, amount: 0, completion: completion)
            }
            approve(token: token, amount: Int64.max, completion: completion)
        }
        return result
    }
    
    func calculateGasForLRC(to amountSell: Double, completion: @escaping (String?, Error?) -> Void) -> Double? {
        var result: Double? = nil
        if let asset = walletManager.getAsset(symbol: "LRC") {
            let lrcAllowance = asset.allowance
            let lrcFee = amountSell * self.lrcFeeInSetting
            let lrcFrozen = getFrozenLRCFeeFromServer()
            let tokenFrozen = getEstimatedAllocatedAllowanceFromServer(token: "LRC")
            if lrcFee + lrcFrozen + tokenFrozen + amountSell > lrcAllowance {
                let gasAmount = gasManager.getGasAmount(by: "approve")
                if lrcAllowance == 0 {
                    result = gasAmount
                } else {
                    result = gasAmount * 2
                    approve(token: "LRC", amount: 0, completion: completion)
                }
                approve(token: "LRC", amount: Int64.max, completion: completion)
            } else {
                return 0
            }
        }
        return result
    }
    
    /* 1. LRC FEE 比较的是当前订单lrc fee + getFrozenLrcfee() >< 账户lrc 余额 不够失败
     2. 如果够了，看lrc授权够不够，够则成功，如果不够需要授权是否等于=0，如果不是，先授权lrc = 0， 再授权lrc = max，是则直接授权lrc = max。看两笔授权支付的eth gas够不够，如果eth够则两次授权，不够失败
     3. 比较当前订单amounts + loopring_getEstimatedAllocatedAllowance() >< 账户授权tokens，够则成功，不够则看两笔授权支付的eth gas够不够，如果eth够则两次授权，不够失败
     如果是sell lrc，需要lrc fee + getFrozenLrcfee() + amounts(lrc) + loopring_getEstimatedAllocatedAllowance() >< 账户授权lrc
     // 4. buy lrc不看前两点，只要3满足即可 */
    func verify(order: OriginalOrder, completion: @escaping (String?, Error?) -> Void) -> Bool {
        if order.side == "buy" {
            if order.tokenBuy.uppercased() == "LRC" {
                return isGasEnough(for: order.tokenSell, to: order.amountSell, includingLRC: false, completion: completion)
            } else {
                return isLRCEnough(to: order.amountSell, completion: completion) && isGasEnough(for: order.tokenSell, to: order.amountSell, includingLRC: true, completion: completion)
            }
        } else {
            if order.tokenSell.uppercased() == "LRC" {
                return isLRCEnough(to: order.amountSell, completion: completion) && isLRCGasEnough(to: order.amountSell, completion: completion)
            } else {
                return isLRCEnough(to: order.amountSell, completion: completion) && isGasEnough(for: order.tokenSell, to: order.amountSell, completion: completion)
            }
        }
    }
    
    func getOrderHash(order: OriginalOrder) -> Data {
        var result: Data = Data()
        result.append(contentsOf: order.delegate.hexBytes)
        result.append(contentsOf: order.address.hexBytes)
        result.append(contentsOf: tokenManager.getContractAddressBySymbol(symbol: order.tokenBuy)!.hexBytes)
        result.append(contentsOf: tokenManager.getContractAddressBySymbol(symbol: order.tokenSell)!.hexBytes)
        let (randomPrivateKey, randomWalletAddress) = Wallet.generateRandomWallet()
        result.append(contentsOf: randomWalletAddress.hexBytes)
        result.append(contentsOf: randomPrivateKey.hexBytes)
        result.append(contentsOf: _encode(order.amountSell, order.tokenSell))
        result.append(contentsOf: _encode(order.amountBuy, order.tokenBuy))
        result.append(contentsOf: _encode(order.validSince))
        result.append(contentsOf: _encode(order.validUntil))
        result.append(contentsOf: _encode(order.lrcFee, "LRC"))
        let flag: [UInt8] = order.buyNoMoreThanAmountB ? [1] : [0]
        result.append(contentsOf: flag)
        result.append(contentsOf: [UInt8(self.marginSplit * 100)])
        return result
    }
    
    func _encode(_ amount: Double, _ token: String) -> [UInt8] {
        let bigInt = GethBigInt.generateBigInt(valueInEther: amount, symbol: token)!
        return try! EthTypeEncoder.default.encode(bigInt).bytes
    }
    
    func _encode(_ value: Int64) -> [UInt8] {
        let bigInt = GethBigInt.init(value)!
        return try! EthTypeEncoder.default.encode(bigInt).bytes
    }
    
    func _encodeString(_ amount: Double, _ token: String) -> String {
        let bigInt = GethBigInt.generateBigInt(valueInEther: amount, symbol: token)!
        return bigInt.hexString
    }
    
    func _submit(order: OriginalOrder, completion: @escaping (String?, Error?) -> Void) {
        let orderData = getOrderHash(order: order)
        SendCurrentAppWalletDataManager.shared._keystore()
        let signature = web3swift.sign(message: orderData)!
        let (authPK, authAddr) = Wallet.generateRandomWallet()
        let walletAddress = RelayAPIConfiguration.orderWalletAddress
        let amountB = _encodeString(order.amountBuy, order.tokenBuy)
        let amountS = _encodeString(order.amountSell, order.tokenSell)
        let lrcFee = _encodeString(order.lrcFee, "LRC")
        let margin = UInt8(marginSplit * 100)
        let validSince = "0x" + String(format: "%2x", order.validSince)
        let validUntil = "0x" + String(format: "%2x", order.validUntil)
  
        LoopringAPIRequest.submitOrder(owner: order.address, walletAddress: walletAddress, tokenS: order.tokenSell, tokenB: order.tokenBuy, amountS: amountS, amountB: amountB, lrcFee: lrcFee, validSince: validSince, validUntil: validUntil, marginSplitPercentage: margin, buyNoMoreThanAmountB: order.buyNoMoreThanAmountB, authAddr: authAddr, authPrivateKey: authPK, v: UInt(signature.v)!, r: signature.r, s: signature.s, completionHandler: completion)
    }
}
