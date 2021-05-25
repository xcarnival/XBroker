const { ethers, upgrades } = require("hardhat");

async function main() {
    Broker = await ethers.getContractFactory(
        "Broker",
    );

    const [deployer] = await ethers.getSigners();
    await upgrades.upgradeProxy('0x6e309eA17eb20f809D53C67476B0ccb90cd68f65', Broker);
    console.log("Broker upgraded");
}

main();