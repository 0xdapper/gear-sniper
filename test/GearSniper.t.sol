import {Test} from "forge-std/Test.sol";
import {GearSniper, IGLB, Stage} from "../src/GearSniper.sol";
import {console} from "forge-std/console.sol";

function generateAddress(string memory seed) pure returns (address) {
    return address(bytes20(keccak256(abi.encode(seed))));
}

contract GearSniperTest is Test {
    GearSniper sniper;
    IGLB constant GLB = IGLB(0xcB91F4521Fc43d4B51586E69F7145606b926b8D4);
    uint FAIR_TRADING_START;
    uint FAIR_TRADING_END;

    address USER_1 = generateAddress("USER_1");
    address USER_2 = generateAddress("USER_2");
    address USER_3 = generateAddress("USER_3");

    function setUp() external {
        sniper = new GearSniper(GLB);
        FAIR_TRADING_START = GLB.fairTradingStart();
        FAIR_TRADING_END = GLB.fairTradingEnd();
    }

    receive() external payable {}

    function testSnipeSuccess() external {
        _commitEthFromUser(USER_1, 2 ether);
        _commitEthFromUser(USER_2, 12 ether);
        _commitEthFromUser(USER_3, 20 ether);

        assertEq(sniper.totalEthCommitted(), 34 ether);
        assertEq(sniper.ethCommitted(USER_1), 2 ether);
        assertEq(sniper.ethCommitted(USER_2), 12 ether);
        assertEq(sniper.ethCommitted(USER_3), 20 ether);

        // forward to fair trading
        vm.warp(FAIR_TRADING_START);

        // snipe and check gear bought
        sniper.snipe();
        uint gearBought = sniper.gearBought();
        assertGt(sniper.gearBought(), 1_500_000e18);

        // check gear balances
        uint user1GearBalance = sniper.gearBalance(USER_1);
        uint user2GearBalance = sniper.gearBalance(USER_2);
        uint user3GearBalance = sniper.gearBalance(USER_3);
        assertEq(
            user1GearBalance,
            (gearBought * 2) / 34,
            "invalid gear balance user 1"
        );
        assertEq(
            user2GearBalance,
            (gearBought * 12) / 34,
            "invalid gear balance user 2"
        );
        assertEq(
            user3GearBalance,
            (gearBought * 20) / 34,
            "invalid gear balance user 3"
        );

        // sell bought gear in fair trading
        vm.prank(USER_1);
        uint balBefore = USER_1.balance;
        sniper.sellGEAR(user1GearBalance);
        uint balAfter = USER_1.balance;
        console.log("sold for eth", balAfter - balBefore);
        assertGt(balAfter, balBefore, "user sold amount");

        uint leftGear = sniper.gearBalance(USER_1);
        assertEq(leftGear, 0, "all gear not sold");

        uint ethLeft = sniper.ethCommitted(USER_1);
        assertEq(ethLeft, 0, "all eth not consumed");

        // claim gear after fair trading ends
        vm.warp(FAIR_TRADING_END);

        GLB.advanceStage();
        vm.prank(USER_2);
        sniper.claimGEAR();
        assertEq(
            sniper.GEAR().balanceOf(USER_2),
            user2GearBalance,
            "full gear not claimed for user 2"
        );
    }

    function testSnipeFailure() external {
        _commitEthFromUser(USER_1, 2 ether);
        _commitEthFromUser(USER_2, 12 ether);
        _commitEthFromUser(USER_3, 20 ether);

        assertEq(sniper.totalEthCommitted(), 34 ether);
        assertEq(sniper.ethCommitted(USER_1), 2 ether);
        assertEq(sniper.ethCommitted(USER_2), 12 ether);
        assertEq(sniper.ethCommitted(USER_3), 20 ether);

        // forward to fair trading and advance
        vm.warp(FAIR_TRADING_START);
        GLB.advanceStage();

        // try snipe
        sniper.snipe();
        assertEq(uint(sniper.stage()), uint(Stage.SNIPING_FAILED));

        // sniping failed, test withdrawals
        vm.prank(USER_1);
        uint balBefore = USER_1.balance;
        sniper.claimETH();
        uint balAfter = USER_1.balance;
        assertEq(balBefore + 2 ether, balAfter);

        // test user cannot withdraw again
        assertEq(sniper.ethCommitted(USER_1), 0);
    }

    function _commitEthFromUser(address _user, uint _amt) internal {
        deal(_user, _amt);
        vm.prank(_user);
        sniper.commitETH{value: _amt}();
    }
}
