const Web3 = require('web3')
const BigNumber = require('bignumber.js')

const rpcURL = "http://localhost:7545"
const web3Client = new Web3(rpcURL)
const userAAddress = "0x71474d7ad130F13f13dd9013E6551d47Bc59bbfe"
const userBAddress = "0xcD1A894d7855571b66A9FBa449AeB9c4C606e355"
const userSwapAddress = "0x1A4f839F3d6Eeda31a61859F5Cea5F33d829CA08"


const swapContract = "0x5DfE3E9ca639A3592cfC2A6aE16Aa6AbB48cD2f2"

web3Client.eth.getBalance(userAAddress, (err, wei) => {
    // 余额单位从wei转换为ether
    balance = web3Client.utils.fromWei(wei, 'ether')
    console.log("balance: " + balance)
})

var poolContract = new web3Client.eth.Contract(
    [{"inputs":[{"internalType":"address","name":"_token","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"spender","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":false,"internalType":"address","name":"fromTokenAddress","type":"address"},{"indexed":true,"internalType":"address","name":"toTokenAddress","type":"address"},{"indexed":false,"internalType":"uint256","name":"fromAmount","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"toAmount","type":"uint256"}],"name":"Exchange","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":false,"internalType":"uint256","name":"liquidityAmount","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"ethAmount","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"tokenAmount","type":"uint256"},{"indexed":false,"internalType":"bool","name":"isAdd","type":"bool"}],"name":"Liquidity","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Transfer","type":"event"},{"inputs":[{"internalType":"uint256","name":"_tokenAmount","type":"uint256"}],"name":"addLiquidity","outputs":[{"internalType":"uint256","name":"liquidity","type":"uint256"}],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"subtractedValue","type":"uint256"}],"name":"decreaseAllowance","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_minTokens","type":"uint256"}],"name":"ethToTokenSwap","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"addedValue","type":"uint256"}],"name":"increaseAllowance","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"name","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"removeLiquidity","outputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"symbol","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_tokenSold","type":"uint256"},{"internalType":"uint256","name":"_minEth","type":"uint256"}],"name":"tokenToEth","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_tokenSold","type":"uint256"},{"internalType":"uint256","name":"_minTokensBought","type":"uint256"},{"internalType":"address","name":"_tokenAddress","type":"address"}],"name":"tokenToTokenSwap","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"transfer","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"from","type":"address"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"transferFrom","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}],
    swapContract,
    {gas: 1000000});

poolContract.methods.
    addLiquidity(100).
    send({from:userAAddress, value: web3Client.utils.toWei("5","ether")},
        function (err, res) {
            if (err) {
            console.log("An error occured", err)
            return
            }
            console.log("addLiquidity: ", res.toString())
        }).
    on('transactionHash', function(hash){
        console.log("hash: ", hash)
        }).
    on('receipt', function(receipt){
            console.log("recepit: ", receipt.events.Liquidity.returnValues) //这里的send调用无法直接获得返回值，只能通过receipt中的event取出事件
        }).
    on('confirmation', function(confirmationNumber, receipt){
            console.log("conffirmation: ", receipt)
        }).
    on('error', console.error);  

poolContract.methods.
    addLiquidity(100).
    send({from:userBAddress, value: web3Client.utils.toWei("5","ether")},
    function (err, res) {
        if (err) {
        console.log("An error occured", err)
        return
        }
        console.log("addLiquidity: ", res.toString())
    }).
    on('transactionHash', function(hash){
        console.log("hash: ", hash)
        }).
    on('receipt', function(receipt){
            console.log("recepit: ", receipt.events.Liquidity.returnValues) //这里的send调用无法直接获得返回值，只能通过receipt中的event取出事件
        }).
    on('confirmation', function(confirmationNumber, receipt){
            console.log("conffirmation: ", receipt)
        }).
    on('error', console.error);  


poolContract.methods.
    ethToTokenSwap(1).
    send({from:userSwapAddress, value: web3Client.utils.toWei("5","ether")},
    function (err, res) {
        if (err) {
        console.log("An error occured", err)
        return
        }
        console.log("swap: ", res.toString())
    }).
    on('transactionHash', function(hash){
        console.log("hash: ", hash)
        }).
    on('receipt', function(receipt){
            console.log("recepit: ", receipt.events.Exchange.returnValues) //这里的send调用无法直接获得返回值，只能通过receipt中的event取出事件
        }).
    on('confirmation', function(confirmationNumber, receipt){
            console.log("conffirmation: ", receipt)
        }).
    on('error', console.error);  

var removeLQ = new BigNumber('500000000000000000')
poolContract.methods.
    removeLiquidity(removeLQ).
    send({from:userAAddress},
        function (err, res) {
            if (err) {
            console.log("An error occured", err)
            return
            }
            console.log("remove: ", res)
        }).
    on('transactionHash', function(hash){
            console.log("hash: ", hash)
        }).
    on('receipt', function(receipt){
            console.log("recepit: ", receipt.events.Liquidity.returnValues) //这里的send调用无法直接获得返回值，只能通过receipt中的event取出事件
        }).
    on('confirmation', function(confirmationNumber, receipt){
            console.log("conffirmation: ", receipt)
        }).
    on('error', console.error);  


