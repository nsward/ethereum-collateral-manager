const ChiefContract = artifacts.require("./src/Chief.sol");
const VaultContract = artifacts.require("./src/Vault.sol");
const ProxyContract = artifacts.require("./src/Proxy.sol");
const ScoutContract = artifacts.require("./src/Oracles/Scout.sol");
const TokenContract = artifacts.require("openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol");
const ValueContract = artifacts.require("./src/Oracles/Value.sol");

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
    await vault.init(chief.address, proxy.address, {from:owner});

    // deploy the medianizer. These will ultimately be already-deployed 
    // MakerDao medianizers
    await deployer.deploy(ValueContract, web3.utils.toHex(price), has)
    const value = await ValueContract.deployed();
    
    // Deploy token contracts separately so they have different addresses
    await deployer.deploy(TokenContract)
    const due = await TokenContract.deployed();
    await deployer.deploy(TokenContract)
    const gem = await TokenContract.deployed();

    // deploy scout with chief and medianizer addresses and the pair to "scout" for
    const pair = web3.utils.soliditySha3(
        {type:'address', value:due.address}, 
        {type:'address', value:gem.address}
    );
    await deployer.deploy(ScoutContract, chief.address, value.address, pair);


    // TODO: remove
    // deployer.deploy(VaultContract).then((vaultInst) =>
    //     deployer.deploy(ProxyContract, vaultInst.address)
    //         .then((proxyInst) => 
    //             deployer.deploy(
    //                 ChiefContract,
    //                 vaultInst.address,
    //                 proxyInst.address
    //             ).then((chiefInst) => 
    //                 vaultInst.init(
    //                     chiefInst.address, 
    //                     proxyInst.address,
    //                     {from:owner}
    //                 )
    //             )
    //         )
    // );
}