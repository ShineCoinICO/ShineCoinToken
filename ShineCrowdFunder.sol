pragma solidity ^0.4.6;

contract SafeMath {
    function mul(uint a, uint b) internal returns (uint) {
        uint c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    function div(uint a, uint b) internal returns (uint) {
        assert(b > 0);
        uint c = a / b;
        assert(a == b * c + a % b);
        return c;
    }

    function sub(uint a, uint b) internal returns (uint) {
        assert(b <= a);
        return a - b;
    }

    function add(uint a, uint b) internal returns (uint) {
        uint c = a + b;
        assert(c >= a);
        return c;
    }
}

contract TokenController {
    function proxyPayment(address _owner) payable returns (bool);

    function onTransfer(address _from, address _to, uint _amount) returns (bool);

    function onApprove(address _owner, address _spender, uint _amount)
    returns (bool);
}


contract Controlled {
    modifier onlyController {if (msg.sender != controller) throw;
        _;}

    address public controller;

    function Controlled() {controller = msg.sender;}

    function changeController(address _newController) onlyController {
        controller = _newController;
    }
}


contract ApproveAndCallFallBack {
    function receiveApproval(address from, uint256 _amount, address _token, bytes _data);
}

contract ShineCrowdFunder is Controlled, SafeMath {
    address public creator;

    address public fundRecipient;

    address public reserveTeamRecipient;

    address public reserveBountyRecipient;

    bool public isReserveGenerated;

    State public state = State.Fundraising;

    uint public minFundingGoal;

    uint public currentBalance;

    uint public tokensIssued;

    uint public capTokenAmount;

    uint public startBlockNumber;

    uint public endBlockNumber;

    uint public tokenExchangeRate;

    ShineCoinToken public exchangeToken;

    event GoalReached(address fundRecipient, uint amountRaised);

    event FundTransfer(address backer, uint amount, bool isContribution);

    event FrozenFunds(address target, bool frozen);

    event LogFundingReceived(address addr, uint amount, uint currentTotal);

    mapping (address => uint256) private balanceOf;

    mapping (address => bool) private frozenAccount;

    enum State {
        Fundraising,
        ExpiredRefund,
        Successful,
        Closed
    }

    modifier inState(State _state) {
        if (state != _state) throw;
        _;
    }

    modifier atEndOfFundraising() {
        if (!((state == State.ExpiredRefund || state == State.Successful) && block.number > endBlockNumber)
        ) {
            throw;
        }
        _;
    }

    modifier accountNotFrozen() {
        if (frozenAccount[msg.sender] == true) throw;
        _;
    }

    modifier minInvestment() {
        // User has to send at least 0.01 Eth
        require(msg.value >= 10 ** 16);
        _;
    }


    function ShineCrowdFunder(
        address _fundRecipient,
        address _reserveTeamRecipient,
        address _reserveBountyRecipient,
        ShineCoinToken _addressOfExchangeToken
    ) {
        creator = msg.sender;

        fundRecipient = _fundRecipient;
        reserveTeamRecipient = _reserveTeamRecipient;
        reserveBountyRecipient = _reserveBountyRecipient;

        isReserveGenerated = false;

        minFundingGoal = 1250 * 1 ether;
        capTokenAmount = 10000000 * 10 ** 9;

        state = State.Fundraising;

        currentBalance = 0;
        tokensIssued = 0;

        startBlockNumber = block.number;
        endBlockNumber = startBlockNumber + ((31 * 24 * 3600) / 18); // 31 days

        tokenExchangeRate = 400 * 10 ** 9;

        exchangeToken = ShineCoinToken(_addressOfExchangeToken);
    }

    function changeReserveTeamRecipient(address _reserveTeamRecipient) onlyController {
        reserveTeamRecipient = _reserveTeamRecipient;
    }

    function changeReserveBountyRecipient(address _reserveBountyRecipient) onlyController {
        reserveBountyRecipient = _reserveBountyRecipient;
    }

    function freezeAccount(address target, bool freeze) onlyController {
        frozenAccount[target] = freeze;
        FrozenFunds(target, freeze);
    }

    function getExchangeRate(uint amount) public constant returns (uint) {
        return tokenExchangeRate * amount / 1 ether;
    }

    function investment() public inState(State.Fundraising) accountNotFrozen minInvestment payable returns (uint)  {
        uint amount = msg.value;
        if (amount == 0) throw;

        balanceOf[msg.sender] += amount;
        currentBalance += amount;

        uint tokenAmount = getExchangeRate(amount);
        exchangeToken.generateTokens(msg.sender, tokenAmount);
        tokensIssued += tokenAmount;

        FundTransfer(msg.sender, amount, true);
        LogFundingReceived(msg.sender, tokenAmount, tokensIssued);

        checkIfFundingCompleteOrExpired();

        return balanceOf[msg.sender];
    }

    function checkIfFundingCompleteOrExpired() {
        if (block.number > endBlockNumber || tokensIssued >= capTokenAmount) {
            if (currentBalance >= minFundingGoal) {
                state = State.Successful;
                payOut();

                GoalReached(fundRecipient, currentBalance);
            }
            else {
                state = State.ExpiredRefund; // backers can now collect refunds by calling getRefund()
            }
        }
    }

    function payOut() public inState(State.Successful) onlyController() {
        var amount = currentBalance;
        currentBalance = 0;
        state = State.Closed;

        fundRecipient.transfer(amount);

        generateReserve();

        exchangeToken.enableTransfers(true);
        exchangeToken.changeReserveTeamRecepient(reserveTeamRecipient);
        exchangeToken.changeController(controller);
    }

    function getRefund() public inState(State.ExpiredRefund) {
        uint amountToRefund = balanceOf[msg.sender];
        balanceOf[msg.sender] = 0;

        msg.sender.transfer(amountToRefund);
        currentBalance -= amountToRefund;

        FundTransfer(msg.sender, amountToRefund, false);
    }

    function generateReserve() {
        if (isReserveGenerated) {
            throw;
        }
        else {
            uint issued = tokensIssued;
            uint percentTeam = 15;
            uint percentBounty = 1;
            uint reserveAmountTeam = div(mul(issued, percentTeam), 85);
            uint reserveAmountBounty = div(mul(issued, percentBounty), 99);
            exchangeToken.generateTokens(reserveTeamRecipient, reserveAmountTeam);
            exchangeToken.generateTokens(reserveBountyRecipient, reserveAmountBounty);
            isReserveGenerated = true;
        }
    }

    function removeContract() public atEndOfFundraising onlyController() {
        if (state != State.Closed) {
            exchangeToken.changeController(controller);
        }
        selfdestruct(msg.sender);
    }

    /* default */
    function() inState(State.Fundraising) accountNotFrozen payable {
        investment();
    }

}