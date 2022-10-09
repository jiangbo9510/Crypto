pragma solidity =0.5.16;

import './interfaces/IUniswapV2Pair.sol';
import './UniswapV2ERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Callee.sol';

contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using SafeMath  for uint;
    using UQ112x112 for uint224;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public token0;
    address public token1;

    //112位的整数，转成uint224需要*2^112
    //2*112_21 = 256，可以存储在一个内存空间
    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    //这个是记录最后一次交易的区块的时间
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;

    //流动性根号(x*y)
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint private unlocked = 1;
    //上锁的装饰器 ，主要避免重入攻击，见../../../Safe目录 
    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;  //这里执行原代码
        unlocked = 1;
    }

    //查询合约记录的余额
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    //支持非标准的ERC20token，兼容openZeppelin的bug，部分token的transfer没有返回值
    //https://jeiwan.net/posts/programming-defi-uniswapv2-2/
    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        //调用成功，并且（函数没有返回，或者 返回了成功）
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'UniswapV2: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    //由Factory合约创建
    constructor() public {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    //初始化两个合约地址，create2不能带参数，只能单独初始化
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    // update reserves and, on the first call per block, price accumulators
    //更新余额，在区块内第一次调用时，更新价格
    //balance0、balance1 是最新的余额，_reserve0、_reserve1是数据更新前的余额
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'UniswapV2: OVERFLOW');
        //时间戳取个余，避免溢出 block.timestamp是int256类型
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        //对比检查是否时第一次调用
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired 兼容溢出情况
            //这里的价格存储，主要是避免出现，通过闪电交易(FlashSwap)，导致价格大幅波动。
            //而外部预言机按照Uniswap价格进行杠杆清算。容易操纵价格，所以这里按照一段时间内的平均价格，计算当前价格。
            //这种价格叫做：Time-Weighted Average Price 时间加权平均价格，简称TWAP
            //累计价格计算 price0CumulativeLast += (reserve1/reserve0)*timeElapsed
            //真正的价格=(PriceT2-PriceT1)/(T2-T1)
            //如果这里blockTimestamp溢出，变的很小，甚至是0，导致timeElapsed非常大，那么在计算T2-T1的时候，会抵消这一部分
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        //更新余额
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        //更新时间戳
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    //添加流动性，添加流动性token
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IUniswapV2Factory(factory).feeTo();//流动性变动是否有手续费
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                //这里是以√(A0*A1)的方式计算pair价值 https://learnblockchain.cn/article/3987
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));//√(_reserve0*_reserve1) //这次mint之前的余额之积的根号
                uint rootKLast = Math.sqrt(_kLast); //rootKLast 是上一个区块开头的余额之积的根号
                if (rootK > rootKLast) {    //两者相等表示中间没人交易，则不需要后续流程。一般不会小于
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint denominator = rootK.mul(5).add(rootKLast);
                    uint liquidity = numerator / denominator;
                    //liquidity = totalSupply* ( rootK - rootKLast)/(rootK*5 + rootKLast) https://learnblockchain.cn/article/3987
                    if (liquidity > 0) _mint(feeTo, liquidity); //给平台抽成的地址也按比例加流动性token
                }
            }
        } else if (_kLast != 0) {

            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    //调用这个接口的合约需要有前置的安全校验
    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint balance0 = IERC20(token0).balanceOf(address(this));   
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);

        //确定是否有手续费
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {    //第一次加流动性
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY); //添加的流动性就是 √(x*y)
            //这里扣减MINIMUM_LIQUIDITY的流动性，主要是避免小LPS(Liquidity Pool Share)有很大的金额，导致后续的人添加流动性成本增加。影响小用户添加流动性
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens //将最小的流动性添加到0地址
        } else {
            //已经有流动性了，那就取0、1token(添加的数量*总流动性/剩余总量)中的较低流动性值
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);   //发放流动性token

        _update(balance0, balance1, _reserve0, _reserve1);  //更新余额
        if (feeOn) kLast = uint(reserve0).mul(reserve1); //有平台手续费，就更新kLast reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    //底层函数，上层合约调用需要进行安全校验
    //退出流动性
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];


        bool feeOn = _mintFee(_reserve0, _reserve1);    //检查是否有平台手续费并结算之
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        //按照LPS比例，结算退出的token数量
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);//销毁流动性token
        _safeTransfer(_token0, to, amount0);//退回token
        _safeTransfer(_token1, to, amount1);//退回token
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);  //更新余额和价格数据
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks //意思是这个函数属于底层函数，调用方需要进行安全校验
    //Param:
    //  amount0Out:转换获得的token0的数量
    //  amount1Out:转换获得的token1的数量
    // 一般情况，amount0Out是0，amount1Out非0，除非是闪电贷
    //  to:获取token的地址
    //  data:
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); //获取余额 gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
        //避免出现爆栈问题
        address _token0 = token0;
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);  //data非空表示需要回调
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        }
        //这里是实际转入的token数量，一般一个为0，一个不为0
        /*
            假设转入的是 token0，转出的是 token1，转入数量为 100，转出数量为 200。那么，下面几个值将如下：
            amount0In = 100
            amount1In = 0
            amount0Out = 0
            amount1Out = 200

            balance0 = reserve0 + amount0In - amout0Out
            反推得到： 
            amountIn = balance - (reserve - amountOut)
        */
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        //(x1-in0*0.003)*(y1 - in1*0.003) >= x0 * y0 ，经过这个公式，表明收了手续费了
        uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
        uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
        require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UniswapV2: K');
        }
        //更新价格等
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    // force reserves to match balances
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}
