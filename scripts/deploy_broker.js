const { ethers, upgrades } = require("hardhat");

var fs = require("fs");

async function main() {

    // npx hardhat run scripts/deploy_broker.js --network bsctest
    // npx hardhat verify --constructor-args scripts/test_for_arguments.js  --network rinkeby
    // npx hardhat verify --network rinkeby 

    // forToken = await ethers.getContractAt("For", '');
    // USDxc = await ethers.getContractFactory("USDxc");
    // MyNFT = await ethers.getContractFactory("MyNFT");
    // let usdxc = await USDxc.deploy("USDxc", "USDxc");
    // let myNFT = await MyNFT.deploy("MyNFT", "MyNFT");
    Broker = await ethers.getContractFactory("Broker");

    const [deployer] = await ethers.getSigners();

    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    console.log("Account balance:", (await deployer.getBalance()).toString());

    console.log("deploy broker...")
    // 生产部署时将 usdxc 的地址换成生产的地址即可
    broker = await upgrades.deployProxy(Broker, [usdxc.address, deployer.address, 120, 120, 0, 0, 0], { initializer: 'initialize' })
    console.log("broker address: ", broker.address);


    var datetime = new Date();
    var output = './deployed_' + datetime + ".json";

    // 实际是为了打印到文件，把 usdxc 和 mynft 的地址替换一下
    var deployed = {
        USDxc: usdxc.address,
        MyNFT: myNFT.address,
        Broker: broker.address
    };

    fs.writeFileSync(output, JSON.stringify(deployed, null, 4));

}

main();