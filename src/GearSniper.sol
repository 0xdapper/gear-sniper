pragma solidity ^0.8.17;

interface IGLB {
    function advanceStage() external;

    function stage() external view returns (uint);

    function fairTradingStart() external view returns (uint);

    function fairTradingEnd() external view returns (uint);

    function buyGEAR(uint256 minGEARBack) external payable;

    function sellGEAR(uint256 amount, uint256 minETHBack) external;

    function curvePool() external view returns (address);
}

interface IGear {
    function balanceOf(address) external view returns (uint);

    function transfer(address _to, uint _amt) external;

    function approve(address _spender, uint _amt) external;
}

enum Stage {
    WAITING,
    SNIPING_FAILED,
    SNIPING_SUCCEEDED
}

contract GearSniper {
    IGLB public immutable glb;
    uint public constant FAIR_TRADING_STAGE = 3;
    uint public constant FINISHED_STAGE = 4;
    IGear public constant GEAR =
        IGear(0xBa3335588D9403515223F109EdC4eB7269a9Ab5D);
    uint public constant SNIPING_FEE_BPS = 10;
    uint public constant TOTAL_FEE_BPS = 10000;

    uint public totalEthCommitted;
    mapping(address => uint) public ethCommitted;
    Stage public stage;
    uint public gearBought;

    address public immutable SNIPER_FEE_RECIPIENT;

    constructor(IGLB _glb) {
        glb = _glb;
        SNIPER_FEE_RECIPIENT = msg.sender;

        GEAR.approve(address(glb), type(uint).max);
    }

    modifier onlyStage(Stage _stage) {
        require(stage == _stage, "invalid stage");
        _;
    }

    // eth received from selling on curve pool
    receive() external payable {}

    function commitETH() external payable {
        _commitETH();
    }

    function rescindEth(uint amt) external onlyStage(Stage.WAITING) {
        totalEthCommitted -= amt;
        ethCommitted[msg.sender] -= amt;
        _sendValue(msg.sender, amt);
    }

    function snipe() external onlyStage(Stage.WAITING) {
        uint start = glb.fairTradingStart();
        require(block.timestamp >= start, "cannot snipe yet");

        if (glb.stage() == 2) {
            glb.advanceStage();

            uint snipingFees = (totalEthCommitted * SNIPING_FEE_BPS) /
                TOTAL_FEE_BPS;
            _sendValue(SNIPER_FEE_RECIPIENT, snipingFees);

            uint totalEthCommittedAfterFees = totalEthCommitted - snipingFees;
            glb.buyGEAR{value: totalEthCommittedAfterFees}(0);

            gearBought = GEAR.balanceOf(address(this));
            stage = Stage.SNIPING_SUCCEEDED;
        } else {
            stage = Stage.SNIPING_FAILED;
        }
    }

    function gearBalance(
        address _user
    ) public view onlyStage(Stage.SNIPING_SUCCEEDED) returns (uint gearClaim) {
        gearClaim = (gearBought * ethCommitted[_user]) / totalEthCommitted;
    }

    function sellGEAR(uint amt) external onlyStage(Stage.SNIPING_SUCCEEDED) {
        uint gearClaim = gearBalance(msg.sender);
        require(amt <= gearClaim, "not enough gear");

        uint committedEth = ethCommitted[msg.sender];
        uint equivalentEth = (amt * committedEth) / gearClaim;
        ethCommitted[msg.sender] -= equivalentEth;

        uint prevBalance = address(this).balance;
        glb.sellGEAR(amt, 0);
        uint afterBalance = address(this).balance;
        uint diffAmt = afterBalance - prevBalance;

        _sendValue(msg.sender, diffAmt);
    }

    function claimGEAR() external onlyStage(Stage.SNIPING_SUCCEEDED) {
        require(
            glb.stage() == 4,
            "fair tradinig stage not ended yet, cannot transfer"
        );

        uint amt = gearBalance(msg.sender);
        delete ethCommitted[msg.sender];
        GEAR.transfer(msg.sender, amt);
    }

    function claimETH() external onlyStage(Stage.SNIPING_FAILED) {
        uint amt = ethCommitted[msg.sender];
        delete ethCommitted[msg.sender];
        _sendValue(msg.sender, amt);
    }

    function _commitETH() internal onlyStage(Stage.WAITING) {
        require(glb.stage() == 2, "can commit eth only in eth deposit stage");
        totalEthCommitted += msg.value;
        ethCommitted[msg.sender] += msg.value;
    }

    function _sendValue(address _to, uint _amt) internal {
        (bool success, bytes memory ret) = payable(_to).call{value: _amt}("");
        uint length = ret.length;
        if (!success)
            assembly {
                revert(ret, add(ret, length))
            }
    }
}
