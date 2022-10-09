pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './interfaces/IUniswapV2Router02.sol';
import './libraries/UniswapV2Library.sol';
import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';

//这里只需要看Router02就行
contract UniswapV2Router02 is IUniswapV2Router02 {
    using SafeMath for uint;

    address public immutable override factory;
    address public immutable override WETH;

    //装饰函数，确保在要求的事件之前完成流动性添加
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;  //这里执行实际的函数
    }

    //WETH是ETH转换为ERC20格式的合约地址
    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // 只允许从WETH合约转入ETH
    }

    // 添加流动性需要的A、Btoken的数量
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,    //前端计算得到的预期需要的A的数量
        uint amountBDesired,    //前端计算得到的预期需要的B的数量
        uint amountAMin,        //用户可以接受的最小的A的数量
        uint amountBMin         //用户可以接受的最小的B的数量
    ) internal virtual returns (uint amountA, uint amountB) {
        // Pair合约不存在，就创建之
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        //这里是先查询pair合约的A、B的余额
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {//这是新合约，第一次添加流动性
            (amountA, amountB) = (amountADesired, amountBDesired); //这里直接返回用户预期的值
        } else {
            //a/x==b/y，a、b是按照余额等比例添加流动性的。这里先算A为基准，所需要的B。
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {//用户提供的B足够，则此次添加需要用户预期的A的数量，等比例的B的数量
                require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {//Btoken的数量不够
                //则以B为基准，计算所需要的A的数量
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    //添加ERC20 token对的流动性
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,    //前端计算得到的预期需要的A的数量
        uint amountBDesired,    //前端计算得到的预期需要的B的数量
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        //计算所需要的A、B的数量
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);   //这里是直接计算得到地址，不用合约调用，节约gas
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA); //转入Atoken到pair合约
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB); //转入Btoken到pair合约
        liquidity = IUniswapV2Pair(pair).mint(to);  //调用pair到mint函数，获取流动性token
    }

    //添加ETH和ERC20交易对的流动性
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,    //前端计算得到的预期需要的token的数量
        uint amountTokenMin,        //用户可以接受的最小的ETH的数量
        uint amountETHMin,          //用户可以接受的最小的token的数量
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        //计算本次所需要的ETH和token的数量
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);//token转账到pair合约
        IWETH(WETH).deposit{value: amountETH}();    //ETH置换为WETH
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IUniswapV2Pair(pair).mint(to);  //开始mint流动性token
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);//多余的ETH退回
    }

    //移除ERC20token交易对的流动性，返回实际需要返还的A、Btoken的数量。这里没有实际的返还，对外的API都在后面
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,         //移除的流动性数量
        uint amountAMin,        //最小获得的A的数量
        uint amountBMin,        //最小获得的B的数量
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); //将流动性token转移到pair
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);   //调用burn函数，得到收回的A、Btoken数量
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);//返回的amount按照token地址的大小的顺序返回，这里要找到数量和token的对应关系
        //检查A、B的数量是否满足用户的要求
        require(amountA >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }

    //溢出ETH、ERC20交易对的流动性
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        //这里转账token
        TransferHelper.safeTransfer(token, to, amountToken);
        //流程和上述的ERC20交易对流动性移除一样，只不过这里多了WETH转换为ETH并转账给to地址
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    //removeLiquidityWithPermit函数的作用
    //正常通过Router移除流动性，需要两步1、调用Pair合约授权流动性token给Router合约，2、调用Router合约移除流动性和相应的流动性token
    //每次操作都需要两次交互，消费两笔gas
    //通过permit操作，通过链外生成签名，跳过approve步骤，节约gas费用
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity; //approveMax==-1表示授权全部
        //这里进行授权后，其余步骤和removeLiquidity一致
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    //removeLiquidityETHWithPermit的作用
    //和上述removeLiquidityWithPermit效果一致
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountETH) {
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        //这里进行授权后，其余步骤和removeLiquidityETH一致
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    //这个移除流动性的方法，主要是用于转账会扣减部分的token，实际到账的token不是传入的金额
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this))); //将Router02合约的所有的token返还给用户
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);  //返还ETH给用户
    }

    //和上一个一样，就是多了个授权的步骤
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountETH) {
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair //swap之前要求先初始化pair合约
    //param:
    //  amount:每次转换获得的token数量
    //  path:最优的转换路径，比如要A换成B，但是A-C-D-B这个转换路径得到的B的数量更多，这种情况，path就是这四个token
    //  关于最优的转换路径：https://mp.weixin.qq.com/s?__biz=MzA5OTI1NDE0Mw==&mid=2652494325&idx=1&sn=59f0017b10da7488d4f262b6177243b7&chksm=8b6853e5bc1fdaf37b191db6eafc4e3625d09001926a2cde625775a76ad986732a2db9218069&token=1269134064&lang=zh_CN&scene=21#wechat_redirect
    //  _to:转换后的转账地址
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            //这里的amount0Out、amount1Out表示转换获得的token0和token1(这里的0、1是按照地址排序后的)的数量，一般情况下一个为0，一个不为0。flash swap的情况下会两个都不为0
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            
            //比如这里A换成C，但是转换得到的C，是给了C-D的合约。如果是最后一次转换，那么就是_to得到最后的token
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            //调用pair合约的转换
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    //ERC20的token之间交换，支付的数量一定，得到的不一定
    //Param:
    //  amountIn:交易的输入的token数量
    //  amountOutMin:获得的最小的token数量
    //  path:完成交换的路径
    //  to:得到token的地址
    //  deadline:交易最后完成时间
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        //计算兑换路径可以得到的token数量
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        //最后得到的要大于amountOutMin
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        //转入token到第一个合约
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        //开始交易
        _swap(amounts, path, to);
    }


    //ERC20交易，但是支付的token不定，得到的token是一定的
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        //计算要得到的amountOut的token，需要的token
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        //得到的token不能高于amountInMax
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]//这个是输入的token
        );
        //开始交易
        _swap(amounts, path, to);
    }


    //ERC20和ETH交易对，用固定ETH交易获得token
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    //ERC20和ETH交易对，用token交换固定的ETH
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    //ERC20和ETH交易对，用固定的token交换ETH
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    //ERC20和ETH交易对，用ETH交换固定的token
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any //退了多余的ETH
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    //支持转账燃烧的token
    //swap之前需要先初始化pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            //根据Input和Output的token，得到pair
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            //https://soliditydeveloper.com/stacktoodeep 原因见这个，主要是函数内使用的变量不能超过16个
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            //amountInput 是输入代币数量
            //amountOutput 是计算可以获得的数量
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            //按照兑换路径，逐次兑换
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    //用固定的ERC20交换另一种ERC20token，支持token交易税
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        //从调用方转入amountIn个token到pair合约
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        //记录to地址的outToken数量
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        //开始交易
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            //to地址得到的token，需要大于用户可以接受的最小值
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    //用固定的ETH交换token，支持token交易税
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        uint amountIn = msg.value;
        //交换为WETH
        IWETH(WETH).deposit{value: amountIn}();
        //把WETH转给pair合约
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    //用固定的token交换ETH，支持token交易税
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        //token转账到pair合约
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        //ETH转给调用方
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    //计算得到的B的数量，amountB = amountA.mul(reserveB) / reserveA，用在添加流动性
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    //计算固定输入可以获得的输出
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    //计算固定的输出，应该输入的数量
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return UniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    //计算通过兑换路径后可以得到的token数量
    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    //计算通过兑换路径后应该输入的token数量
    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}
