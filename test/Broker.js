const { expect } = require("chai");
const { BN, time } = require('@openzeppelin/test-helpers');

async function timeIncreaseTo(seconds) {
    const delay = 10 - new Date().getMilliseconds();
    await new Promise(resolve => setTimeout(resolve, delay));
    await time.increaseTo(seconds);
}

describe("Broker contract", function () {

    let Broker;
    let USDxc;
    let usdcx;

    beforeEach(async function () {
        [addr1, addr2, ...addrs] = await ethers.getSigners();
        Broker = await ethers.getContractFactory("Broker");
        USDxc = await ethers.getContractFactory("USDxc");
        usdcx = await USDcx.deploy("USDxc", "USDxc");
        await usdcx.mint1000W();
    });

});
