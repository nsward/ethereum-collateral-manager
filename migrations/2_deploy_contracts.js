const ChiefContract = artifacts.require("./src/Chief.sol");
const VaultContract = artifacts.require("./src/Vault.sol");
const ProxyContract = artifacts.require("./src/Proxy.sol");
const SpotterContract = artifacts.require("./src/Oracles/Spotter.sol");
const TokenContract = artifacts.require("openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol");
const OracleContract = artifacts.require("./src/Oracles/Oracle.sol");

// Deploying:
// 1. deploy vault (no constructor)
// 2. deploy proxy with vault as constructor argument
// 3. deploy chief with vault and proxy as constructor arguments
// 4. call Vault.init()

module.exports = async function(deployer, network, accounts) {
    const owner = accounts[0];
    const price = 100;          // initial due/gem spot price
    const has = true;

    // deploy vault
    await deployer.deploy(VaultContract);
    const vault = await VaultContract.deployed();

    // deploy proxy with vault address
    await deployer.deploy(ProxyContract, vault.address)
    const proxy = await ProxyContract.deployed();

    // TODO: if proxy address in chief is just for getter. should delete in case it changes
    // deploy chief with proxy and vault addresses
    await deployer.deploy(ChiefContract, vault.address)
    const chief = await ChiefContract.deployed();

    // Pass chief and proxy addresses to vault contract
    await vault.initAuthContracts(chief.address, proxy.address, {from:owner});

    // deploy the medianizer. These will ultimately be already-deployed 
    // MakerDao medianizers
    await deployer.deploy(OracleContract, web3.utils.toHex(price), has)
    const oracle = await OracleContract.deployed();
    
    // Deploy token contracts separately so they have different addresses
    await deployer.deploy(TokenContract)
    const dueToken = await TokenContract.deployed();
    await deployer.deploy(TokenContract)
    const tradeToken = await TokenContract.deployed();

    // deploy spotter with chief and medianizer addresses and the pair to "spot" for
    const pair = web3.utils.soliditySha3(
        {type:'address', value:dueToken.address}, 
        {type:'address', value:tradeToken.address}
    );
    await deployer.deploy(SpotterContract, chief.address, oracle.address, pair);

}