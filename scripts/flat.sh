echo "deploy begin....."

TF_CMD=node_modules/.bin/truffle-flattener

TOKEN_LIST=( StrategyDForce)
for contract in ${TOKEN_LIST[@]};
do
    echo $contract
    $TF_CMD ./contracts/dforce/$contract.sol > $contract.full.sol
    mv $contract.full.sol ./deployments/$contract.full.sol 
done

echo "deploy  end....."