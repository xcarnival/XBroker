const { ethers, upgrades } = require("hardhat");

var fs = require("fs");

async function main() {

    // npx hardhat run scripts/deploy_broker.js --network bsctest
    // npx hardhat verify --constructor-args scripts/test_for_arguments.js  --network rinkeby
    // npx hardhat verify --network rinkeby 
    // npx hardhat verify 0xbd1f6dc5e218aa41734f6ab7ff7a125d4ad536e6 --network bsctest

    // forToken = await ethers.getContractAt("For", '');
    // USDxc = await ethers.getContractFactory("USDxc");
    // MyNFT = await ethers.getContractFactory("MyNFT");
    // let usdxc = await USDxc.deploy("USDxc", "USDxc");
    // let myNFT = await MyNFT.deploy("MyNFT", "MyNFT");
    Broker = await ethers.getContractFactory("BrokerV2");

    const [deployer] = await ethers.getSigners();

    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    console.log("Account balance:", (await deployer.getBalance()).toString());

    console.log("deploy broker...")
    // 生产部署时将 usdxc 的地址换成生产的地址即可
    var usdxc = "0x8B340114D07033696FA901b010d0995b38D7FF93"; // megabox stable coin
    var _beneficiary = "0x2937e407665785372D70fDf67677f477B8a32499"; // 
    var _redemptionPeriod = 0;
    var _clearingPeriod = 86400;
    broker = await upgrades.deployProxy(Broker, [usdxc, _beneficiary, _redemptionPeriod, _clearingPeriod, 100, 0, 100], { initializer: 'initialize' })
    console.log("broker address: ", broker.address);

    // 默认最大出借人数量
    await broker.setDefaultMaxLendersCnt(100);
    var megabox_broker = "0xA11b0a75B784a6D5ac44021F40d1E26fEcB62329";
    await broker.setPubSubMgr(megabox_broker);

    var datetime = new Date();
    var output = './deployed_' + datetime + ".json";

    // 实际是为了打印到文件，把 usdxc 和 mynft 的地址替换一下
    var deployed = {
        // USDxc: usdxc.address,
        // MyNFT: myNFT.address,
        USDxc: usdxc,
        // MyNFT: "0x9615ADB5Ac2832CAbDC74B597c3c50D556e3005B",
        Broker: broker.address
    };

    fs.writeFileSync(output, JSON.stringify(deployed, null, 4));

}

main();