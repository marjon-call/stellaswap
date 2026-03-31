.PHONY: build

build:
	@if [ -f nexus_build_result.yaml ]; then \
		echo "nexus_build_result.yaml already exists, skipping build."; \
		exit 0; \
	fi; \
	git submodule update --init --recursive && \
	cd lib/openzeppelin-contracts && git checkout v4.8.0 && cd ../.. && \
	cd lib/openzeppelin-contracts-upgradeable && git checkout v4.8.0 && cd ../.. && \
	forge build && \
	printf 'language: solidity\nbuild_targets:\n  - .\ninstallation_script: "git submodule update --init --recursive && cd lib/openzeppelin-contracts && git checkout v4.8.0 && cd ../.. && cd lib/openzeppelin-contracts-upgradeable && git checkout v4.8.0 && cd ../.. && forge build"\nrun_test_command: "MOONBEAM_RPC_URL=https://rpc.api.moonbeam.network forge test"\ndeveloper_note: "OpenZeppelin submodules must be pinned to v4.8.0. The default HEAD is v5 which breaks imports."\nblocking_error: ""\n' > nexus_build_result.yaml && \
	echo "nexus_build_result.yaml created successfully."
