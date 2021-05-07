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
    let MyNFT;

    let broker;
    let usdxc;
    let myNFT;

    beforeEach(async function () {
        [addr1, addr2, addr3, addr4, ...addrs] = await ethers.getSigners();
        Broker = await ethers.getContractFactory("Broker");
        USDxc = await ethers.getContractFactory("USDxc");
        usdxc = await USDxc.deploy("USDxc", "USDxc");
        broker = await upgrades.deployProxy(Broker, [usdxc.address, addr1.address, 86400 * 2, 86400 * 2, 0, 0, 0], { initializer: 'initialize' })
        await usdxc.mint1000W();

        MyNFT = await ethers.getContractFactory("MyNFT");
        myNFT = await MyNFT.deploy("MyNFT", "MyNFT");
        await myNFT.connect(addr2).mint();
    });

    describe("Deployment", function () {
        it("Should set the right usdxc", async function () {
            expect(await broker.usdxc()).to.equal(usdxc.address);
            // console.log(await broker.usdxc());
        });
    });

    describe("Transaction", function () {
        it("Pledge", async function () {
            await myNFT.connect(addr2).approve(broker.address, 0);
            await broker.connect(addr2).pledge(myNFT.address, 0, ethers.utils.parseEther('100'), ethers.utils.parseEther('10'), 86400 * 30);
        });

        it("Pledge And Cancel", async function () {
            await myNFT.connect(addr2).approve(broker.address, 0);
            await broker.connect(addr2).pledge(myNFT.address, 0, ethers.utils.parseEther('100'), ethers.utils.parseEther('10'), 86400 * 30);
            await broker.connect(addr2).cancelPledge(myNFT.address, 0);
        });

        it("Cannot Pledge twice", async function () {
            await myNFT.connect(addr2).approve(broker.address, 0);
            await broker.connect(addr2).pledge(myNFT.address, 0, ethers.utils.parseEther('100'), ethers.utils.parseEther('10'), 86400 * 30)
            // await expect(
            //     await broker.connect(addr2).pledge(myNFT.address, 0, 0, ethers.utils.parseEther('10'), 86400 * 30)
            // ).to.be.revertedWith("Invalid price");
            // await expect(
            //     await broker.connect(addr2).pledge(myNFT.address, 0, ethers.utils.parseEther('100'), ethers.utils.parseEther('10'), 86400 * 30)
            // ).to.be.revertedWith("Invalid NFT status");
        });

        it("lender makes offer", async function () {
            await myNFT.connect(addr2).approve(broker.address, 0);
            await broker.connect(addr2).pledge(myNFT.address, 0, ethers.utils.parseEther('100'), ethers.utils.parseEther('10'), 86400 * 30)
            await usdxc.connect(addr3).mint1000W();
            await usdxc.connect(addr3).approve(broker.address, ethers.utils.parseEther('1000000000'));
            await broker.connect(addr3).lenderOffer(myNFT.address, 0, ethers.utils.parseEther('90'), ethers.utils.parseEther('10'));
        });

        it("lender cancel offer", async function () {
            await myNFT.connect(addr2).approve(broker.address, 0);
            await broker.connect(addr2).pledge(myNFT.address, 0, ethers.utils.parseEther('100'), ethers.utils.parseEther('10'), 86400 * 30)
            await usdxc.connect(addr3).mint1000W();
            await usdxc.connect(addr3).approve(broker.address, ethers.utils.parseEther('1000000000'));
            await broker.connect(addr3).lenderOffer(myNFT.address, 0, ethers.utils.parseEther('90'), ethers.utils.parseEther('10'));
            await broker.connect(addr3).lenderCancelOffer(myNFT.address, 0);
        });

        it("lender deal", async function () {
            await myNFT.connect(addr2).approve(broker.address, 0);
            await broker.connect(addr2).pledge(myNFT.address, 0, ethers.utils.parseEther('100'), ethers.utils.parseEther('10'), 86400 * 30)
            await usdxc.connect(addr3).mint1000W();
            await usdxc.connect(addr3).approve(broker.address, ethers.utils.parseEther('1000000000'));
            await broker.connect(addr3).lenderDeal(myNFT.address, 0);
        });
    });

});
