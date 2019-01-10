const VaultContract = artifacts.require("./src/Vault.sol");
const ProxyContract = artifacts.require("./src/Proxy.sol");
const ChiefContract = artifacts.require("./src/Chief.sol");

// Deploying:
// 1. deploy vault (no constructor)
// 2. deploy proxy with vault as constructor argument
// 3. deploy chief with vault and proxy as constructor arguments
// 4. call Vault.init()

module.exports = function(deployer, network, accounts) {
    const owner = accounts[0];

    deployer.deploy(VaultContract).then((vaultInst) =>
        deployer.deploy(ProxyContract, vaultInst.address)
            .then((proxyInst) => 
                deployer.deploy(
                    ChiefContract,
                    vaultInst.address,
                    proxyInst.address
                ).then((chiefInst) => 
                    vaultInst.init(
                        chiefInst.address, 
                        proxyInst.address,
                        {from:owner}
                    )
                )
            )
    );
}