// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * If you are reading data feeds on L2 networks, you must
 * check the latest answer from the L2 Sequencer Uptime
 * Feed to ensure that the data is accurate in the event
 * of an L2 sequencer outage. See the
 * https://docs.chain.link/data-feeds/l2-sequencer-feeds
 * page for details.
 */

contract PriceRetriever is Ownable {
    AggregatorV3Interface public dataFeed;

    uint8 public feed_decimals;
    uint8 public token_decimals;

    constructor() Ownable() {    }

    function init( address aggregator, uint8 _token_decimals) external {
        dataFeed = AggregatorV3Interface(aggregator);
        feed_decimals = dataFeed.decimals();
        token_decimals = _token_decimals;
    }

    /**
     * Returns the latest answer.
     */
    function getChainlinkDataFeedLatestAnswer() public view returns (int) {
        // prettier-ignore
        (
            /* uint80 roundId */,
            int256 answer,
            /*uint256 startedAt*/,
            /*uint256 updatedAt*/,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return answer;
    }

    function getPriceFeed() internal view returns (int256) {
        return getChainlinkDataFeedLatestAnswer();
    }

    function getPriceInWei() external view returns (uint256) {
        int256 price = getChainlinkDataFeedLatestAnswer();
        require(price > 0, "Price must be positive");
        if( feed_decimals >= token_decimals) {
            return uint256(price) / (10 ** uint256(feed_decimals - token_decimals));
        }
        else{
            return uint256(price) * (10 ** uint256(token_decimals - feed_decimals));
        }
    }
}
