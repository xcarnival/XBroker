const { ethers, upgrades } = require("hardhat");

var fs = require("fs");

async function main() {

    // npx hardhat run scripts/deploy_dao.js --network rinkeby
    // npx hardhat verify --constructor-args scripts/test_for_arguments.js  --network rinkeby
    // npx hardhat verify --network rinkeby 

    // forToken = await ethers.getContractAt("For", '');
    USDxc = await ethers.getContractFactory("USDxc");
    MyNFT = await ethers.getContractFactory("MyNFT");
    let usdxc = await USDxc.deploy("USDxc", "USDxc");
    let myNFT = await MyNFT.deploy("MyNFT", "MyNFT");
    Broker = await ethers.getContractFactory("Broker");

    const [deployer] = await ethers.getSigners();

    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    console.log("Account balance:", (await deployer.getBalance()).toString());

    console.log("deploy broker...")
    broker = await upgrades.deployProxy(Broker, [usdxc.address, deployer.address, 1800, 1800, 0, 0, 0], { initializer: 'initialize' })
    console.log("broker address: ", broker.address);


    var datetime = new Date();
    var output = './deployed_' + datetime + ".json";

    var deployed = {
        USDxc: usdxc.address,
        MyNFT: myNFT.address,
        Broker: broker.address
    };

    fs.writeFileSync(output, JSON.stringify(deployed, null, 4));

}

main();