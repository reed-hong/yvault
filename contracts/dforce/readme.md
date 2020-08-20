# 说明

StrategyDForce实现DForce的香槟塔池挖矿： https://staking.dforce.network/

用户存入DAI/USDT/USDC到yVault中，策略逻辑会把这些token转为会想要的dDai/dUSDT/dUSDC，拿着这些token去pool里面质押，获得df

目录中的DTokenProxy.sol， DToken.sol 是dToken系列中dUSDC的一种实现，供参考和测试用。

另外，为了方便维护，把代码做了分拆，抽取了部分公共的Inteface和Library。

可以通过脚本：

npm run flat

合并代码，放在目录/deployments下：StrategyDForce.full.sol





