# XBroker
Xbroker is a platform for NFT pledging to borrow cryptocoin, which provides liquidity to the NFT market. And Xbroker is divided into three roles :borrower, lender, liquidator, borrower is the role of providing NFT to pledge after borrowing cryptocoin, lender is to lend USDxc to get interest, liquidator is through the auction call way to participate in the liquidation that pay hammer price to get NFT.

# Workflow
XBroker has three types of roles involved, namely mortgagor, lender, and liquidator.
Mortgagor: Stakeholders obtain USDxc by staking NFT, and redeem their NFT by repaying the principal and interest of USDxc.
Lender: The lender chooses the NFT mortgaged by the mortgagor, and lends USDxc to the mortgagor. After the mortgagor returns the USDxc and interest, the system will return the NFT to the mortgagor, and transfer the principal and interest to the lender.
Liquidator: If the mortgagor does not plan for USDxc within the time limit, the system will auction the NFT. The starting price is the sum of the NFT’s loan price and interest. The auction is a mark-up auction. If a liquidator bids for the NFT, the system will transfer the NFT. To the liquidator, and transfer the USDxc issued by the liquidator to the lender. If it fails, the NFT will eventually be owned by the lender.

