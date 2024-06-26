// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PPFX} from "../src/PPFX.sol";
import {IPPFX} from "../src/IPPFX.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract USDT is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _mint(_msgSender(), 100_000_000 ether);
    }
}

contract PPFXTest is Test {
    using MessageHashUtils for bytes32;
    
    PPFX public ppfx;
    USDT public usdt;
    PPFX public proxyPpfx; 
    address public treasury = address(123400);
    address public insurance = address(1234500);

    uint256 internal userPrivateKey;
    uint256 internal signerPrivateKey;
    address internal signerAddr;

    function setUp() public {
        usdt = new USDT("USDT", "USDT");
        
        ppfx = new PPFX();

        ppfx.initialize(
            address(this),
            treasury,
            insurance,
            IERC20(address(usdt)),
            5,
            1,
            "test_version"
        );

        ppfx.addOperator(address(this));

        userPrivateKey = 0xa11ce;
        signerPrivateKey = 0xabc123;
        signerAddr = vm.addr(signerPrivateKey);

        ppfx.updateWithdrawHook(address(this));
    }

    function test_SuccessDeposit() public {
        usdt.approve(address(ppfx), 1 ether);
        ppfx.deposit(1 ether);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_AddMarket() public {
        ppfx.addMarket("BTC");
        assertEq(ppfx.totalMarkets(), 1);
    }

    function test_SuccessWithdraw() public {
        test_SuccessDeposit();
        ppfx.withdraw(1 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 1 ether);
        vm.warp(block.timestamp + 5);
        uint256 oldBalance = usdt.balanceOf(address(this));
        ppfx.claimPendingWithdrawal();
        assertEq(usdt.balanceOf(address(this)), oldBalance + 1 ether);
    }

    function test_SuccessLiquidateAndClosePositionSameAmount() public {
        ppfx.addMarket("BTC");
        usdt.approve(address(ppfx), 5000);
        ppfx.deposit(5000);
        usdt.transfer(address(1), 5000);

        vm.startPrank(address(1));
        usdt.approve(address(ppfx), 5000);
        ppfx.deposit(5000);
        vm.stopPrank();

        ppfx.addPosition(address(1), "BTC", 5000, 0);
        ppfx.addPosition(address(this), "BTC", 5000, 0);

        ppfx.liquidate(address(1), "BTC", 100, 0);
        ppfx.closePosition(address(this), "BTC", 4900, true, 0);

        assertEq(ppfx.userFundingBalance(address(this)), 4900 + 5000);
    }

    function test_SuccessLiquidateAndClosePositionDiffAmount() public {
        ppfx.addMarket("BTC");
        usdt.approve(address(ppfx), 5000);
        ppfx.deposit(5000);
        usdt.transfer(address(1), 5500);

        vm.startPrank(address(1));
        usdt.approve(address(ppfx), 5500);
        ppfx.deposit(5500);
        vm.stopPrank();

        ppfx.addPosition(address(1), "BTC", 5500, 0);
        ppfx.addPosition(address(this), "BTC", 5000, 0);

        ppfx.liquidate(address(1), "BTC", 100, 0);
        ppfx.closePosition(address(this), "BTC", 5400, true, 0);

        assertEq(ppfx.userFundingBalance(address(this)), 5400 + 5000);
    }

    function test_SuccessWithdrawTwice() public {
        usdt.approve(address(ppfx), 2 ether);
        ppfx.deposit(2 ether);
        assertEq(ppfx.totalBalance(address(this)), 2 ether);

        ppfx.withdraw(1 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 1 ether);
        vm.warp(block.timestamp + 2);
        ppfx.withdraw(1 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 2 ether);
        vm.warp(block.timestamp + 7);
        uint256 oldBalance = usdt.balanceOf(address(this));
        ppfx.claimPendingWithdrawal();
        assertEq(usdt.balanceOf(address(this)), oldBalance + 2 ether);
    }

    function test_SuccessAddOperator() public {
        assertEq(ppfx.getAllOperators().length, 1);
        ppfx.addOperator(address(1));
        assertEq(ppfx.getAllOperators().length, 2);
    }

    function test_SuccessRemoveOperator() public {
        assertEq(ppfx.getAllOperators().length, 1);
        ppfx.addOperator(address(1));
        assertEq(ppfx.getAllOperators().length, 2);
        ppfx.removeOperator(address(1));
        assertEq(ppfx.getAllOperators().length, 1);
    }

    function test_SuccessRemoveAllOperators() public {
        assertEq(ppfx.getAllOperators().length, 1);
        ppfx.addOperator(address(1));
        assertEq(ppfx.getAllOperators().length, 2);

        ppfx.removeAllOperator();
        assertEq(ppfx.getAllOperators().length, 0);
        assertEq(ppfx.isOperator(address(1)), false);

        ppfx.addOperator(address(555));
        assertEq(ppfx.getAllOperators().length, 1);
        ppfx.addOperator(address(6666));
        assertEq(ppfx.getAllOperators().length, 2);
        
        ppfx.removeAllOperator();
        assertEq(ppfx.getAllOperators().length, 0);
    }

    function test_SuccessWithdrawAllThenAddPosition() public {
        test_SuccessDeposit();
        test_AddMarket();
        ppfx.withdraw(1 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 1 ether);
        ppfx.addPosition(address(this), "BTC", 1 ether - 1, 1);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 0);
        assertEq(ppfx.userFundingBalance(address(this)), 0);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_SuccessWithdrawHalfThenAddPosition() public {
        test_SuccessDeposit();
        test_AddMarket();
        ppfx.withdraw(0.5 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 0.5 ether);
        ppfx.addPosition(address(this), "BTC", 0.8 ether - 1, 1);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 0);
        assertEq(ppfx.userFundingBalance(address(this)), 0.2 ether);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_SuccessWithdrawThenAddPositionWithEnoughFundingBalance() public {
        test_SuccessDeposit();
        test_AddMarket();
        ppfx.withdraw(0.5 ether);
        ppfx.addPosition(address(this), "BTC", 0.4 ether - 1, 1);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 0.5 ether);
        assertEq(ppfx.userFundingBalance(address(this)), 0.1 ether);
        assertEq(ppfx.totalBalance(address(this)), 0.5 ether);
    }

    function test_SuccessAddPosition() public {
        test_SuccessDeposit();
        test_AddMarket();
        ppfx.addPosition(address(this), "BTC", 1 ether - 1, 1);

        assertEq(ppfx.userFundingBalance(address(this)), 0);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_2ndAddrSuccessAddPosition() public {
        usdt.transfer(address(1), 1 ether);

        vm.startPrank(address(1));
        usdt.approve(address(ppfx), 1 ether);
        ppfx.deposit(1 ether);
        vm.stopPrank();

        if (!ppfx.marketExists(keccak256(bytes("BTC")))) {
            test_AddMarket();
        }
        
        ppfx.addPosition(address(1), "BTC", 1 ether - 1, 1);
    }

    function test_SuccessReduceEntirePositionNoProfit() public {
        test_SuccessAddPosition();
        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);
        ppfx.reducePosition(address(this), "BTC", 1 ether - 1, 0, false, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.userFundingBalance(address(this)), 1 ether - 1);
        assertEq(ppfx.totalBalance(address(this)), 1 ether - 1);
    }

    function test_SuccessReduceEntirePositionWithProfit() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        // Bob Short BTC with 1,000,000,000,000 USDT
        test_2ndAddrSuccessAddPosition(); 

        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);

        // Alice Close Position Entire Position, with 1,000,000,000,000 USDT Profit
        ppfx.reducePosition(address(this), "BTC", 1 ether - 1, 1 ether - 1, true, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);

        assertEq(ppfx.userFundingBalance(address(this)), 2 ether - 2);
        assertEq(ppfx.totalBalance(address(this)), 2 ether - 2);
        
        // Bob Liquidate entire position 
        ppfx.liquidate(address(1), "BTC", 0, 1);

        // Bob should have no balance left
        assertEq(ppfx.totalBalance(address(1)), 0);
    }

    function test_SuccessReducePositionOnlyProfit() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        // Bob Short BTC with 1,000,000,000,000 USDT
        test_2ndAddrSuccessAddPosition(); 

        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);
        // Alice Reduce Position, Getting 1,000,000,000,000 USDT Profit
        // With no reduce in her position
        ppfx.reducePosition(address(this), "BTC", 1, 1 ether, true, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.userFundingBalance(address(this)), 1 ether + 1);
        assertEq(ppfx.totalBalance(address(this)), 2 ether - 1);

        // Bob Liquidate entire position 
        ppfx.liquidate(address(1), "BTC", 0, 1);

        // Bob should have no balance left
        assertEq(ppfx.totalBalance(address(1)), 0);
    }

    function test_SuccessReduceHalfPositionWithAllProfit() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        // Bob Short BTC with 1,000,000,000,000 USDT
        test_2ndAddrSuccessAddPosition(); 

        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);
        // Alice Reduce Position, Reducing half of her position,
        // and getting 1,000,000,000,000 USDT Profit
        ppfx.reducePosition(address(this), "BTC", 0.5 ether, 1 ether, true, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.userFundingBalance(address(this)), 1.5 ether);
        assertEq(ppfx.totalBalance(address(this)), 2 ether - 1);

        // Bob Liquidate entire position 
        ppfx.liquidate(address(1), "BTC", 0, 1);

        // Bob should have no balance left
        assertEq(ppfx.totalBalance(address(1)), 0);
    }

    function test_SuccessReduceHalfPositionWithHalfProfit() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        // Bob Short BTC with 1,000,000,000,000 USDT
        test_2ndAddrSuccessAddPosition(); 

        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);
        // Alice Reduce Position, Reducing half of her position,
        // and getting 500,000,000,000 USDT Profit
        ppfx.reducePosition(address(this), "BTC", 0.5 ether, 0.5 ether, true, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.userFundingBalance(address(this)), 1 ether);
        assertEq(ppfx.totalBalance(address(this)), 1.5 ether - 1);

        // Bob lose half of his position
        ppfx.reducePosition(address(1), "BTC", 0.5 ether, 0.5 ether, false, 0);
        // Bob should have half of his balance left
        assertEq(ppfx.totalBalance(address(1)), 0.5 ether);
    }

    function test_SuccessReduceNoProfitPosition() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);

        // Alice Reduce Position, lose fee
        ppfx.reducePosition(address(this), "BTC", 1, 0, false, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.userFundingBalance(address(this)), 1);
        assertEq(ppfx.totalBalance(address(this)), 1 ether - 1);
    }

    function test_SuccessCloseEntirePositionNoProfit() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        // Bob Short BTC with 1,000,000,000,000 USDT
        test_2ndAddrSuccessAddPosition(); 

        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);
        // Alice close position with 100% loss
        ppfx.closePosition(address(this), "BTC", 1 ether - 1, false, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.userFundingBalance(address(this)), 0);
        assertEq(ppfx.totalBalance(address(this)), 0);
    }

    function test_SuccessCloseHalfPositionNoProfit() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        // Bob Short BTC with 1,000,000,000,000 USDT
        test_2ndAddrSuccessAddPosition(); 

        // Alice close position with 50% loss
        ppfx.closePosition(address(this), "BTC", 0.5 ether, false, 0);

        assertEq(ppfx.userFundingBalance(address(this)), 0.5 ether);

        assertEq(ppfx.totalBalance(address(this)), 0.5 ether);
        assertEq(ppfx.marketTotalTradingBalance(keccak256(bytes("BTC"))), 1.5 ether);

        // Bob close position with 50% winning
        ppfx.closePosition(address(1), "BTC", 0.5 ether, true, 0);
        assertEq(ppfx.userFundingBalance(address(this)), 0.5 ether);
        assertEq(ppfx.totalBalance(address(1)), 1.5 ether);
    }

    function test_SuccessFillOrder() public {
        test_SuccessAddPosition();
        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);

        ppfx.fillOrder(address(this), "BTC", 1 gwei);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1 gwei);
        assertEq(ppfx.userFundingBalance(address(this)), 0);
        assertEq(ppfx.totalBalance(address(this)), 1 ether - 1 gwei);
    }

    function test_SuccessFillOrderAllBalanceAsFee() public {
        test_SuccessAddPosition();
        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);

        ppfx.fillOrder(address(this), "BTC", 1 ether);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1 ether);
        assertEq(ppfx.totalBalance(address(this)), 0);
    }

    function test_SuccessCancelOrder() public {
        test_SuccessAddPosition();

        ppfx.cancelOrder(address(this), "BTC", 1 ether - 1, 1);

        assertEq(ppfx.userFundingBalance(address(this)), 1 ether);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_SuccessCancelHalfOrder() public {
        test_SuccessAddPosition();

        ppfx.cancelOrder(address(this), "BTC", 1 ether / 2, 1);

        assertEq(ppfx.userFundingBalance(address(this)), 1 ether / 2 + 1);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_SuccessAddFunding() public {
        test_SuccessAddPosition();

        // Deduct funding fee
        ppfx.settleFundingFee(address(this), "BTC", 0.5 ether, false);
        // Then Add funding fee
        ppfx.settleFundingFee(address(this), "BTC", 0.5 ether, true);

        assertEq(ppfx.userFundingBalance(address(this)), 0.5 ether);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_SuccessDeductFunding() public {
        test_SuccessAddPosition();

        ppfx.settleFundingFee(address(this), "BTC", 1 ether, false);

        assertEq(ppfx.userFundingBalance(address(this)), 0);
        assertEq(ppfx.totalBalance(address(this)), 0);
    }

    function test_SuccessLiquidateEntireBalance() public {
        test_SuccessAddPosition();

        ppfx.liquidate(address(this), "BTC", 1 gwei, 1 gwei);

        assertEq(usdt.balanceOf(insurance), 1 gwei);
        assertEq(ppfx.totalBalance(address(this)), 1 gwei);
    }

    function test_SuccessLiquidateHalfBalance() public {
        test_SuccessAddPosition();
        uint256 bal = ppfx.getTradingBalanceForMarket(address(this), "BTC");
        ppfx.liquidate(address(this), "BTC", bal / 2, 1 gwei);

        assertEq(usdt.balanceOf(insurance), 1 gwei);
        assertEq(ppfx.userFundingBalance(address(this)), bal / 2);
    }

    function test_SuccessAddCollateral() public {
        test_SuccessAddPosition();
        
        usdt.approve(address(ppfx), 1 ether);
        ppfx.deposit(1 ether);
        assertEq(ppfx.userFundingBalance(address(this)), 1 ether);

        ppfx.addCollateral(address(this), "BTC", 1 ether);

        assertEq(ppfx.userFundingBalance(address(this)), 0);
        assertEq(ppfx.totalBalance(address(this)), 2 ether);
    }

    function test_SuccessReduceCollateral() public {
        test_SuccessAddPosition();

        ppfx.reduceCollateral(address(this), "BTC", 1 ether);

        assertEq(ppfx.userFundingBalance(address(this)), 1 ether);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_SuccessBulkPositionUpdates() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        bytes[] memory bs = new bytes[](40);
        for (uint256 i = 0; i < 30; i++) {
            bs[i] = abi.encodeWithSelector(ppfx.addPosition.selector, address(this), "BTC", 1 gwei, 0);
        }
        for (uint256 i = 30; i < 40; i++) {
            bs[i] = abi.encodeWithSelector(ppfx.reducePosition.selector, address(this), "BTC", 1 gwei, 0, false, 0);
        }

        ppfx.bulkProcessFunctions(bs);

        assertEq(ppfx.userFundingBalance(address(this)), 1 ether - 20 gwei);
    }

    function test_SuccessSingleBulkPositionUpdates() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        bytes[] memory bs = new bytes[](1);
        for (uint256 i = 0; i < 1; i++) {
            bs[i] = abi.encodeWithSelector(ppfx.addCollateral.selector, address(this), "BTC", 1 gwei, 0);
        }

        ppfx.bulkProcessFunctions(bs);

        assertEq(ppfx.userFundingBalance(address(this)), 1 ether - 1 gwei);
    }

    function test_Success20BulkPositionUpdates() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        bytes[] memory bs = new bytes[](20);
        for (uint256 i = 0; i < 20; i++) {
            bs[i] = abi.encodeWithSelector(ppfx.addCollateral.selector, address(this), "BTC", 1 gwei, 0);
        }

        ppfx.bulkProcessFunctions(bs);

        assertEq(ppfx.userFundingBalance(address(this)), 1 ether - 20 gwei);
    }

    function test_Success10BulkPositionUpdates() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        bytes[] memory bs = new bytes[](10);
        for (uint256 i = 0; i < 10; i++) {
            bs[i] = abi.encodeWithSelector(ppfx.addCollateral.selector, address(this), "BTC", 1 gwei, 0);
        }

        ppfx.bulkProcessFunctions(bs);

        assertEq(ppfx.userFundingBalance(address(this)), 1 ether - 10 gwei);
    }

    function test_SuccessBulkPositionUpdatesPartiallyFailed() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        bytes[] memory bs = new bytes[](30);
        for (uint256 i = 0; i < 10; i++) {
            bs[i] = abi.encodeWithSelector(ppfx.addCollateral.selector, address(this), "BTC", 1 gwei, 0);
        }
        for (uint256 i = 10; i < 30; i++) {
            bs[i] = abi.encodeWithSelector(0x12345678, address(this), "BTC", 1 gwei, 0, false, 0, false);
        }

        ppfx.bulkProcessFunctions(bs);

        assertEq(ppfx.userFundingBalance(address(this)), 1 ether - 10 gwei);
    }

    function test_SuccessEmptyBulkPositionUpdates() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        bytes[] memory bs = new bytes[](0);

        ppfx.bulkProcessFunctions(bs);

        assertEq(ppfx.userFundingBalance(address(this)), 1 ether);
    }

    function test_SuccessDepositForUser() public {
        assertEq(ppfx.totalBalance(signerAddr), 0);
        uint256 usdtBalBefore = usdt.balanceOf(address(this));
        usdt.approve(address(ppfx), 1 ether);
        ppfx.depositForUser(signerAddr, 1 ether);
        assertEq(usdt.balanceOf(address(this)), usdtBalBefore - 1 ether);
        assertEq(ppfx.totalBalance(signerAddr), 1 ether);
    }

    function test_SuccessWithdrawForUser() public {
        
        // Transfer USDT from this address to address 1
        usdt.transfer(signerAddr, 1 ether);

        // Deposit to PPFX
        vm.startPrank(signerAddr);
        usdt.approve(address(ppfx), 1 ether);
        ppfx.deposit(1 ether);
        vm.stopPrank();
        
        uint48 signedAt = uint48(block.timestamp);
        uint256 withdrawAmount = 1 ether;

        IPPFX.DelegateData memory out = createWithdrawData(address(this), signedAt, withdrawAmount);

        ppfx.withdrawForUser(address(this), signerAddr, 1 ether, out);
        assertEq(ppfx.pendingWithdrawalBalance(signerAddr), 1 ether);
    }

    function test_SuccessClaimForUser() public {
        
        // Transfer USDT from this address to address 1
        usdt.transfer(signerAddr, 1 ether);

        // Deposit to PPFX
        vm.startPrank(signerAddr);
        usdt.approve(address(ppfx), 1 ether);
        ppfx.deposit(1 ether);
        ppfx.withdraw(1 ether);
        vm.stopPrank();
        assertEq(ppfx.pendingWithdrawalBalance(signerAddr), 1 ether);
        vm.warp(block.timestamp + 5);
        
        uint48 signedAt = uint48(block.timestamp);

        IPPFX.DelegateData memory out = createClaimData(address(this), signedAt);

        uint256 usdtBalBeforeClaim = usdt.balanceOf(address(this));

        ppfx.claimPendingWithdrawalForUser(address(this), signerAddr, out);

        assertEq(ppfx.totalBalance(signerAddr), 0);
        assertEq(usdt.balanceOf(address(this)), usdtBalBeforeClaim + 1 ether);
    }

    function test_Fail_TooManyOperators() public {
        uint256 max = ppfx.MAX_OPERATORS() + 1;
        for (uint i = 1; i < max; i++) {
            ppfx.addOperator(address(uint160(i)));
        }
        vm.expectRevert(bytes("Too many operators"));
        ppfx.addOperator(address(uint160(444)));
    }

    function test_Fail_DepositZero() public {
        vm.expectRevert(bytes("Invalid amount"));
        ppfx.deposit(0);
    }

    function test_Fail_NoAllowanceDeposit() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(ppfx), 0, 1 ether));
        ppfx.deposit(1 ether);
    }

    function test_Fail_NoAllowanceDepositMax() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(ppfx), 0, 2**256-1));
        ppfx.deposit(2**256-1);
    }

    function test_Fail_withdrawMax() public {
        vm.expectRevert(bytes("Insufficient balance from funding account"));
        ppfx.withdraw(2**256-1);
    }

    function test_Fail_withdrawZero() public {
        vm.expectRevert(bytes("Invalid amount"));
        ppfx.withdraw(0);
    }

    function test_Fail_UpdateInvalidWithdrawalBlockTime() public {
        vm.expectRevert(bytes("Invalid new wait time"));
        ppfx.updateWithdrawalWaitTime(0);
    }

    function test_Fail_WithdrawBeforeAvailable() public {
        test_SuccessDeposit();
        ppfx.withdraw(1 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 1 ether);
        vm.warp(block.timestamp + 2);
        vm.expectRevert(bytes("No available pending withdrawal to claim"));
        ppfx.claimPendingWithdrawal();
    }

    function test_Fail_WithdrawTwiceBeforeAvailable() public {
        usdt.approve(address(ppfx), 2 ether);
        ppfx.deposit(2 ether);
        assertEq(ppfx.totalBalance(address(this)), 2 ether);

        ppfx.withdraw(1 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 1 ether);
        vm.warp(block.timestamp + 2);
        ppfx.withdraw(1 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 2 ether);
        vm.warp(block.timestamp + 4);
        vm.expectRevert(bytes("No available pending withdrawal to claim"));
        ppfx.claimPendingWithdrawal();
    }

    function test_Fail_WithdrawAllThenAddPosition() public {
        test_SuccessDeposit();
        test_AddMarket();
        ppfx.withdraw(1 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 1 ether);
        vm.expectRevert(bytes("Insufficient funding balance to add position"));
        ppfx.addPosition(address(this), "BTC", 1 ether, 1);
    }

    function test_Fail_WithdrawHalfThenAddPosition() public {
        test_SuccessDeposit();
        test_AddMarket();
        ppfx.withdraw(0.5 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 0.5 ether);
        vm.expectRevert(bytes("Insufficient funding balance to add position"));
        ppfx.addPosition(address(this), "BTC", 1 ether, 1);
    }

    function test_Fail_AddPositionInsufficientBalanceForFee() public {
        test_SuccessDeposit();
        test_AddMarket();
        vm.expectRevert(bytes("Insufficient funding balance to add position"));
        ppfx.addPosition(address(this), "BTC", 1 ether, 1);
    }

    function test_Fail_AddPositionInsufficientBalance() public {
        test_SuccessDeposit();
        test_AddMarket();

        vm.expectRevert(bytes("Insufficient funding balance to add position"));
        ppfx.addPosition(address(this), "BTC", 1 ether + 1, 0);
    }

    function test_Fail_ReducePositionInsufficientBalanceForFee() public {
        test_SuccessAddPosition();

        vm.expectRevert(bytes("Insufficient trading balance to reduce position"));
        ppfx.reducePosition(address(this), "BTC", 1 ether, 0, false, 1);
    }

    function test_Fail_ReducePositionInsufficientBalance() public {
        test_SuccessAddPosition();

        vm.expectRevert(bytes("Insufficient trading balance to settle uPNL"));
        ppfx.reducePosition(address(this), "BTC", 1 ether, 1 ether + 1, false, 0);
       
    }

    function test_Fail_ClosePositionInsufficientBalanceForFee() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        // Bob Short BTC with 1,000,000,000,000 USDT
        test_2ndAddrSuccessAddPosition(); 

        // Alice close position with 100% profit
        ppfx.closePosition(address(this), "BTC", 1 ether, true, 0);

        // Bob close position with 100% profit which couldn't happen
        vm.expectRevert(bytes("uPNL profit will cause market insolvency"));
        ppfx.closePosition(address(1), "BTC", 1 ether, true, 0);

        
    }

    function test_Fail_ClosePositionCauseInsolvency() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        
        // Close position with 1,000,000,000,001 USDT Porfit
        vm.expectRevert(bytes("uPNL profit will cause market insolvency"));
        ppfx.closePosition(address(this), "BTC", 1 ether + 1000000, true, 0);
    }

    function test_Fail_FillOrderInsufficientBalance() public {
        test_SuccessAddPosition();
        vm.expectRevert(bytes("Insufficient trading balance to pay order filling fee"));
        ppfx.fillOrder(address(this), "BTC", 2 ether);
    }

    function test_Fail_CancelOrderInsufficientBalanceForFee() public {
        test_SuccessAddPosition();
        vm.expectRevert(bytes("Insufficient trading balance to cancel order"));
        ppfx.cancelOrder(address(this), "BTC", 1 ether, 1);
    }

    function test_Fail_CancelOrderInsufficientBalance() public {
        test_SuccessAddPosition();
        vm.expectRevert(bytes("Insufficient trading balance to cancel order"));
        ppfx.cancelOrder(address(this), "BTC", 1 ether + 1, 0);
    }

    function test_Fail_SettleFundingFeeInsufficientCollectedFeeToAdd() public {
        test_SuccessAddPosition();
        vm.expectRevert(bytes("Insufficient collected funding fee to add funding fee"));
        ppfx.settleFundingFee(address(this), "BTC", 1 ether, true);
    }

    function test_Fail_SettleFundingFeeInsufficientTradingBalanceToDeduct() public {
        test_SuccessAddPosition();
        vm.expectRevert(bytes("Insufficient trading balance to deduct funding fee"));
        ppfx.settleFundingFee(address(this), "BTC", 1 ether + 1, false);
    }

    function test_Fail_LiquidateInsufficientBalanceForFee() public {
        test_SuccessAddPosition();
        vm.expectRevert(bytes("Insufficient trading balance to liquidate"));
        ppfx.liquidate(address(this), "BTC", 1 ether, 1);
    }

    function test_Fail_LiquidateInsufficientBalance() public {
        test_SuccessAddPosition();
        vm.expectRevert(bytes("Insufficient trading balance to liquidate"));
        ppfx.liquidate(address(this), "BTC", 1 ether + 1, 0);
    }

    function test_Fail_AddCollateralInsufficientBalance() public {
        test_SuccessAddPosition();
        vm.expectRevert(bytes("Insufficient funding balance to add collateral"));
        ppfx.addCollateral(address(this), "BTC", 1);
    }

    function test_Fail_ReduceCollateralInsufficientBalance() public {
        test_SuccessAddPosition();
        vm.expectRevert(bytes("Insufficient trading balance to reduce collateral"));
        ppfx.reduceCollateral(address(this), "BTC", 1 ether + 1);
    }

    function test_Fail_NotAdmin() public {
        vm.startPrank(address(0));

        vm.expectRevert(bytes("Caller not admin"));
        ppfx.updateTreasury(address(1));
        
        vm.expectRevert(bytes("Caller not admin"));
        ppfx.updateInsurance(address(1));

        vm.expectRevert(bytes("Caller not admin"));
        ppfx.updateUsdt(address(1));

        vm.expectRevert(bytes("Caller not admin"));
        ppfx.updateWithdrawalWaitTime(1);

        vm.stopPrank();
    }

    function test_AdminFunctions() public {
        ppfx.updateTreasury(address(1));
        assertEq(ppfx.treasury(), address(1));

        ppfx.updateInsurance(address(2));
        assertEq(ppfx.insurance(), address(2));

        ppfx.updateUsdt(address(3));
        assertEq(address(ppfx.usdt()), address(3));

        ppfx.updateWithdrawalWaitTime(444);
        assertEq(ppfx.withdrawalWaitTime(), 444);
    }

    function test_Fail_NotAdminAddOperator() public {
        vm.startPrank(address(0));
        vm.expectRevert(bytes("Caller not admin"));
        ppfx.addOperator(address(1));
    }

    function test_Fail_NotAdminRemoveOperator() public {
        vm.startPrank(address(0));
        vm.expectRevert(bytes("Caller not admin"));
        ppfx.removeOperator(address(this));
    }

    function test_Fail_NotAdminRemoveAllOperators() public {
        vm.startPrank(address(0));
        vm.expectRevert(bytes("Caller not admin"));
        ppfx.removeAllOperator();
    }

    function test_Fail_RemoveNotExistsOperator() public {
        vm.expectRevert(bytes("Operator does not exists"));
        ppfx.removeOperator(address(3));
    }

    function test_Fail_NoOperatorRemoveAllOperators() public {
        ppfx.removeAllOperator();
        assertEq(ppfx.getAllOperators().length, 0);
        vm.expectRevert(bytes("No operator found"));
        ppfx.removeAllOperator();
    }

    function test_Fail_NotOperator() public {
        vm.startPrank(address(0));

        vm.expectRevert(bytes("Caller not operator"));
        ppfx.addPosition(address(this), "BTC", 1, 1);
        
        vm.expectRevert(bytes("Caller not operator"));
        ppfx.reducePosition(address(this), "BTC", 1, 0, false, 1);

        vm.expectRevert(bytes("Caller not operator"));
        ppfx.closePosition(address(this), "BTC", 1, false, 1);
        
        vm.expectRevert(bytes("Caller not operator"));
        ppfx.fillOrder(address(this), "BTC", 1);

        vm.expectRevert(bytes("Caller not operator"));
        ppfx.cancelOrder(address(this), "BTC", 1, 1);

        vm.expectRevert(bytes("Caller not operator"));
        ppfx.settleFundingFee(address(this), "BTC", 1, false);

        vm.expectRevert(bytes("Caller not operator"));
        ppfx.liquidate(address(this), "BTC", 1, 1);

        vm.expectRevert(bytes("Caller not operator"));
        ppfx.addCollateral(address(this), "BTC", 1);

        vm.expectRevert(bytes("Caller not operator"));
        ppfx.reduceCollateral(address(this), "BTC", 1);

        vm.stopPrank();
    }

    function test_Fail_CallWithNotExistsMarket() public {
        vm.expectRevert(bytes("Provided market does not exists"));
        ppfx.addPosition(address(this), "BTC", 1, 1);

        vm.expectRevert(bytes("Provided market does not exists"));
        ppfx.reducePosition(address(this), "BTC", 1, 0, false, 1);

        vm.expectRevert(bytes("Provided market does not exists"));
        ppfx.closePosition(address(this), "BTC", 1, false, 1);

        vm.expectRevert(bytes("Provided market does not exists"));
        ppfx.fillOrder(address(this), "BTC", 1);

        vm.expectRevert(bytes("Provided market does not exists"));
        ppfx.cancelOrder(address(this), "BTC", 1, 1);

        vm.expectRevert(bytes("Provided market does not exists"));
        ppfx.settleFundingFee(address(this), "BTC", 1, false);

        vm.expectRevert(bytes("Provided market does not exists"));
        ppfx.liquidate(address(this), "BTC", 1, 1);

        vm.expectRevert(bytes("Provided market does not exists"));
        ppfx.addCollateral(address(this), "BTC", 1);

        vm.expectRevert(bytes("Provided market does not exists"));
        ppfx.reduceCollateral(address(this), "BTC", 1);
    }

    function test_Fail_TransferAdminNotAllowed() public {
        vm.startPrank(address(0));

        vm.expectRevert(bytes("Caller not admin"));
        ppfx.transferAdmin(address(1));
        
        vm.stopPrank();
    }

    function test_SuccessTransferAdmin() public {
        ppfx.transferAdmin(address(4));

        vm.startPrank(address(4));

        ppfx.acceptAdmin();
        assertEq(ppfx.admin(), address(4));

        vm.stopPrank();
    }

    function test_Fail_AcceptAdmin() public {
        ppfx.transferAdmin(address(4));

        vm.startPrank(address(5));
        vm.expectRevert(bytes("Caller not pendingAdmin"));
        ppfx.acceptAdmin();
    }

    function test_Fail_WithdrawForUser_Expired() public {
        
        // Transfer USDT from this address to address 1
        usdt.transfer(signerAddr, 1 ether);

        // Deposit to PPFX
        vm.startPrank(signerAddr);
        usdt.approve(address(ppfx), 1 ether);
        ppfx.deposit(1 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 200);
        
        uint48 signedAt = uint48(block.timestamp-200);
        uint256 withdrawAmount = 1 ether;

        IPPFX.DelegateData memory out = createWithdrawData(address(this), signedAt, withdrawAmount);
        
        vm.expectRevert(bytes("Invalid Delegate Data"));
        ppfx.withdrawForUser(address(this), signerAddr, 1 ether, out);
    }

    function test_Fail_ClaimForUser_Expired() public {
        
        // Transfer USDT from this address to address 1
        usdt.transfer(signerAddr, 1 ether);

        // Deposit to PPFX
        vm.startPrank(signerAddr);
        usdt.approve(address(ppfx), 1 ether);
        ppfx.deposit(1 ether);
        ppfx.withdraw(1 ether);
        vm.stopPrank();
        assertEq(ppfx.pendingWithdrawalBalance(signerAddr), 1 ether);
        vm.warp(block.timestamp + 5);

        vm.warp(block.timestamp + 200);

        uint48 signedAt = uint48(block.timestamp-5);
        
        IPPFX.DelegateData memory out = createClaimData(address(this), signedAt);

        vm.expectRevert(bytes("Invalid Delegate Data"));
        ppfx.claimPendingWithdrawalForUser(address(this), signerAddr, out);
    }

    function test_Fail_WithdrawForUser_NotDelegate() public {
        
        // Transfer USDT from this address to address 1
        usdt.transfer(signerAddr, 1 ether);

        // Deposit to PPFX
        vm.startPrank(signerAddr);
        usdt.approve(address(ppfx), 1 ether);
        ppfx.deposit(1 ether);
        vm.stopPrank();

        uint48 signedAt = uint48(block.timestamp);
        uint256 withdrawAmount = 1 ether;

        IPPFX.DelegateData memory out = createWithdrawData(address(this), signedAt, withdrawAmount);

        vm.expectRevert(bytes("Invalid Delegate Data"));
        // Delegate in signature is `signedAddr`, but in function call it is `address(1)`
        ppfx.withdrawForUser(address(1), signerAddr, 1 ether, out);
    }

    function test_Fail_ClaimForUser_NotDelegate() public {
        
        // Transfer USDT from this address to address 1
        usdt.transfer(signerAddr, 1 ether);

        // Deposit to PPFX
        vm.startPrank(signerAddr);
        usdt.approve(address(ppfx), 1 ether);
        ppfx.deposit(1 ether);
        ppfx.withdraw(1 ether);
        vm.stopPrank();
        assertEq(ppfx.pendingWithdrawalBalance(signerAddr), 1 ether);
        vm.warp(block.timestamp + 5);

        uint48 signedAt = uint48(block.timestamp);

        IPPFX.DelegateData memory out = createClaimData(address(this), signedAt);

        vm.expectRevert(bytes("Invalid Delegate Data"));
        // Delegate in signature is `signedAddr`, but in function call it is `address(1)`
        ppfx.claimPendingWithdrawalForUser(address(1), signerAddr, out);
    }

    function test_Fail_WithdrawForUser_SignedByAnotherUser() public {
        
        // Transfer USDT from this address to address 1
        usdt.transfer(signerAddr, 1 ether);

        // Deposit to PPFX
        vm.startPrank(signerAddr);
        usdt.approve(address(ppfx), 1 ether);
        ppfx.deposit(1 ether);
        vm.stopPrank();

        uint48 deadline = uint48(block.timestamp) + 200;
        uint256 withdrawAmount = 1 ether;

        bytes32 digest = ppfx.getWithdrawHash(
            signerAddr,
            address(this),
            withdrawAmount,
            deadline
        );

        // Supposed to be signed by `signerPrivateKey`
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        IPPFX.DelegateData memory out = IPPFX.DelegateData(signerAddr, address(this), withdrawAmount, deadline, signature);

        vm.expectRevert(bytes("Invalid Delegate Data"));
        ppfx.withdrawForUser(address(this), signerAddr, 1 ether, out);
    }

    function test_Fail_ClaimForUser_SignedByAnotherUser() public {
        
        // Transfer USDT from this address to address 1
        usdt.transfer(signerAddr, 1 ether);

        // Deposit to PPFX
        vm.startPrank(signerAddr);
        usdt.approve(address(ppfx), 1 ether);
        ppfx.deposit(1 ether);
        ppfx.withdraw(1 ether);
        vm.stopPrank();
        assertEq(ppfx.pendingWithdrawalBalance(signerAddr), 1 ether);
        vm.warp(block.timestamp + 5);

        uint48 deadline = uint48(block.timestamp) + 200;

        bytes32 digest = ppfx.getClaimHash(
            signerAddr,
            address(this),
            deadline
        );

        // Supposed to be signed by `signerPrivateKey`
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        IPPFX.DelegateData memory out = IPPFX.DelegateData(signerAddr, address(this), 0, deadline, signature);

        vm.expectRevert(bytes("Invalid Delegate Data"));
        ppfx.claimPendingWithdrawalForUser(address(this), signerAddr, out);
    }

    function test_Fail_WithdrawForUser_Reuse_signature() public {
        
        // Transfer USDT from this address to address 1
        usdt.transfer(signerAddr, 1 ether);

        // Deposit to PPFX
        vm.startPrank(signerAddr);
        usdt.approve(address(ppfx), 1 ether);
        ppfx.deposit(1 ether);
        vm.stopPrank();
        
        uint48 signedAt = uint48(block.timestamp);
        uint256 withdrawAmount = 0.5 ether;

        IPPFX.DelegateData memory out = createWithdrawData(address(this), signedAt, withdrawAmount);

        ppfx.withdrawForUser(address(this), signerAddr, 0.5 ether, out);
        assertEq(ppfx.pendingWithdrawalBalance(signerAddr), 0.5 ether);

        vm.expectRevert(bytes("Invalid Delegate Data"));
        ppfx.withdrawForUser(address(this), signerAddr, 0.5 ether, out);
    }

    function test_Fail_WithdrawForUser_Not_Hook() public {
        
        // Transfer USDT from this address to address 1
        usdt.transfer(signerAddr, 1 ether);

        // Deposit to PPFX
        vm.startPrank(signerAddr);
        usdt.approve(address(ppfx), 1 ether);
        ppfx.deposit(1 ether);
        vm.stopPrank();
        
        uint48 signedAt = uint48(block.timestamp);
        uint256 withdrawAmount = 0.5 ether;

        IPPFX.DelegateData memory out = createWithdrawData(address(this), signedAt, withdrawAmount);

        vm.startPrank(address(0x12345678));
        vm.expectRevert(bytes("Caller not withdraw hook"));
        ppfx.withdrawForUser(address(this), signerAddr, 0.5 ether, out);
        vm.stopPrank();
    }

    function test_Fail_ClaimForUser_Not_Hook() public {
        
        // Transfer USDT from this address to address 1
        usdt.transfer(signerAddr, 2 ether);

        // Deposit to PPFX
        vm.startPrank(signerAddr);
        usdt.approve(address(ppfx), 2 ether);
        ppfx.deposit(1 ether);
        ppfx.withdraw(0.5 ether);
        vm.stopPrank();
        assertEq(ppfx.pendingWithdrawalBalance(signerAddr), 0.5 ether);
        vm.warp(block.timestamp + 5);
        
        uint48 signedAt = uint48(block.timestamp);

        IPPFX.DelegateData memory out = createClaimData(address(this), signedAt);

        vm.startPrank(address(0x12345678));
        vm.expectRevert(bytes("Caller not withdraw hook"));
        ppfx.claimPendingWithdrawalForUser(address(this), signerAddr, out);
        vm.stopPrank();
    }

    function test_Fail_ClaimForUser_Reuse_signature() public {
        
        // Transfer USDT from this address to address 1
        usdt.transfer(signerAddr, 2 ether);

        // Deposit to PPFX
        vm.startPrank(signerAddr);
        usdt.approve(address(ppfx), 2 ether);
        ppfx.deposit(1 ether);
        ppfx.withdraw(0.5 ether);
        vm.stopPrank();
        assertEq(ppfx.pendingWithdrawalBalance(signerAddr), 0.5 ether);
        vm.warp(block.timestamp + 5);
        
        uint48 signedAt = uint48(block.timestamp);

        IPPFX.DelegateData memory out = createClaimData(address(this), signedAt);

        uint256 usdtBalBeforeClaim = usdt.balanceOf(address(this));

        ppfx.claimPendingWithdrawalForUser(address(this), signerAddr, out);

        assertEq(ppfx.totalBalance(signerAddr), 0.5 ether);
        assertEq(usdt.balanceOf(address(this)), usdtBalBeforeClaim + 0.5 ether);

        vm.startPrank(signerAddr);
        ppfx.withdraw(0.5 ether);
        vm.stopPrank();
        assertEq(ppfx.pendingWithdrawalBalance(signerAddr), 0.5 ether);
        vm.warp(block.timestamp + 5);

        vm.expectRevert(bytes("Invalid Delegate Data"));
        ppfx.claimPendingWithdrawalForUser(address(this), signerAddr, out);
    }

    // Internal function for creating the data & signature //

    function createWithdrawData(
        address delegate,
        uint48 deadline,
        uint256 withdrawAmount
    ) internal view returns (IPPFX.DelegateData memory) {
        bytes32 digest = ppfx.getWithdrawHash(
            signerAddr,
            delegate,
            withdrawAmount,
            deadline
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        return IPPFX.DelegateData(signerAddr, delegate, withdrawAmount, deadline, signature);
    }

    function createClaimData(
        address delegate,
        uint48 deadline
    ) internal view returns (IPPFX.DelegateData memory) {
        bytes32 digest = ppfx.getClaimHash(
            signerAddr,
            delegate,
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

       return IPPFX.DelegateData(signerAddr, delegate, 0, deadline, signature);
    }
}
