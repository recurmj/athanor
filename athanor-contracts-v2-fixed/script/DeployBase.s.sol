// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {AthanorConsentRegistry} from "../src/AthanorConsentRegistry.sol";
import {AthanorPullExecutor} from "../src/AthanorPullExecutor.sol";
import {AthanorStrategyAllowlist} from "../src/AthanorStrategyAllowlist.sol";

contract DeployBase is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        AthanorConsentRegistry registry = new AthanorConsentRegistry();
        AthanorPullExecutor executor = new AthanorPullExecutor(address(registry));

        // trust executor so it can recordPull()
        registry.setTrustedExecutor(address(executor), true);

        AthanorStrategyAllowlist strategy = new AthanorStrategyAllowlist(deployer);
        strategy.setExecutor(address(executor));

        string memory targets = vm.envOr("ALLOWLIST_TARGETS", string(""));
        if (bytes(targets).length > 0) {
            string[] memory parts = _split(targets, ",");
            for (uint256 i = 0; i < parts.length; i++) {
                address t = vm.parseAddress(parts[i]);
                strategy.setAllowed(t, true);
            }
        }

        vm.stopBroadcast();

        console2.log("REGISTRY=", address(registry));
        console2.log("EXECUTOR=", address(executor));
        console2.log("STRATEGY=", address(strategy));
    }

    function _split(string memory s, string memory delim) internal pure returns (string[] memory) {
        bytes memory b = bytes(s);
        bytes memory d = bytes(delim);
        uint256 count = 1;
        for (uint256 i = 0; i + d.length <= b.length; i++) {
            bool matchDelim = true;
            for (uint256 j = 0; j < d.length; j++) if (b[i + j] != d[j]) { matchDelim = false; break; }
            if (matchDelim) count++;
        }
        string[] memory out = new string[](count);
        uint256 start = 0;
        uint256 idx = 0;
        for (uint256 i = 0; i + d.length <= b.length; i++) {
            bool matchDelim = true;
            for (uint256 j = 0; j < d.length; j++) if (b[i + j] != d[j]) { matchDelim = false; break; }
            if (matchDelim) {
                out[idx++] = string(b[start:i]);
                start = i + d.length;
                i += d.length - 1;
            }
        }
        out[idx] = string(b[start:b.length]);
        return out;
    }
}
