import { expect } from "chai";
import { ethers } from "hardhat";
// import { PierMarketplace, ERC20 } from "../typechain"; // Adjust import paths based on your project structure
import { PierMarketplace, ERC20 } from "../typechain-types";

describe("PierMarketplace - book function", function () {
  let marketplace: PierMarketplace;
  let sellToken: ERC20;
  let paymentToken: ERC20;
  let owner;
  let addr1: any; 
  let addr2;

  beforeEach(async function () {
    // Deploying the marketplace and token contracts
    [owner, addr1, addr2] = await ethers.getSigners();

    const Marketplace = await ethers.getContractFactory("PierMarketplace");
    marketplace = await Marketplace.deploy(owner.address);

    const ERC20Token = await ethers.getContractFactory("Mock");
    sellToken = await ERC20Token.deploy("SellToken", "ST");
    paymentToken = await ERC20Token.deploy("PaymentToken", "PT");

    // Distribute some tokens to addr1
    await sellToken.mint(addr1.address, ethers.utils.parseUnits("1000", 18));
    await paymentToken.mint(addr1.address, ethers.utils.parseUnits("1000", 18));
  });

  it("Should create a new book listing successfully", async function () {
    const sellTokenAmount = ethers.utils.parseUnits("100", 18);
    const paymentTokenAmount = ethers.utils.parseUnits("50", 18);

    // Approving marketplace to spend addr1's tokens
    await sellToken.connect(addr1).approve(marketplace.address, sellTokenAmount);

    // Create a new book listing
    await expect(
      marketplace.connect(addr1).book(sellToken.address, sellTokenAmount, paymentToken.address, paymentTokenAmount)
    )
    .to.emit(marketplace, "Booked")
    .withArgs(1, addr1.address, sellToken.address, sellTokenAmount, paymentToken.address, paymentTokenAmount);

    // Verify the book listing details
    const book = await marketplace.bookList(1);
    expect(book.seller).to.equal(addr1.address);
    expect(book.sellTokenAddress).to.equal(sellToken.address);
    expect(book.sellTokenAmount).to.equal(sellTokenAmount);
    expect(book.paymentTokenAddress).to.equal(paymentToken.address);
    expect(book.paymentTokenAmount).to.equal(paymentTokenAmount);
    expect(book.isActive).to.be.true;
  });

  it("Should fail if sell token amount is 0", async function () {
    await expect(marketplace.connect(addr1).book(sellToken.address, 0, paymentToken.address, 100))
    .to.be.revertedWith("InvalidSellTokenAmount");
  });

  it("Should fail if payment token amount is 0", async function () {
    await expect(marketplace.connect(addr1).book(sellToken.address, 100, paymentToken.address, 0))
    .to.be.revertedWith("InvalidPaymentTokenAmount");
  });

  it("Should fail if sell token address is zero address", async function () {
    await expect(marketplace.connect(addr1).book(ethers.constants.AddressZero, 100, paymentToken.address, 100))
    .to.be.revertedWith("InvalidSellTokenAddress");
  });

  it("Should fail if payment token address is zero address", async function () {
    await expect(marketplace.connect(addr1).book(sellToken.address, 100, ethers.constants.AddressZero, 100))
    .to.be.revertedWith("InvalidPaymentTokenAddress");
  });

  it("Should fail if marketplace does not have enough allowance to transfer tokens", async function () {
    await expect(marketplace.connect(addr1).book(sellToken.address, ethers.utils.parseUnits("100", 18), paymentToken.address, ethers.utils.parseUnits("50", 18)))
    .to.be.revertedWith("Marketplace does not have enough allowance to transfer tokens");
  });
});
