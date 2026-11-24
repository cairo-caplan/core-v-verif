// Copyright 2023 OpenHW Group
// Copyright (c) 2026 Eclipse Foundation
//
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://solderpad.org/licenses/
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`ifndef __RVFI_SPIKE_SV__
`define __RVFI_SPIKE_SV__

// Core-independent bridge from an OpenHW core configuration to a tandem Spike
// run. It is mainly composed by two functions:
//
//   - rvfi_cfg_to_profile(): takes st_core_cntrl_cfg and returns a profile
//   - rvfi_initialize_spike(): applies the profile and 
//     calls rvfi_start_spike() to start Spike

/**
 * Fill a profile from the generic core configuration. Only derivable values
 * are set here; everything else keeps rvfi_profile_defaults. The
 * +config_file=<path> override is recorded in the profile and applied by
 * rvfi_apply_spike_profile.
 */
function automatic rvfi_spike_profile_t rvfi_cfg_to_profile(string core_name,
                                                            st_core_cntrl_cfg core_cfg);
    rvfi_spike_profile_t p;

    p = rvfi_profile_defaults();

    p.profile_name = core_name;
    p.hart_id      = int'(core_cfg.mhartid);

    p.isa  = get_isa_str(core_cfg);
    p.priv = get_priv_str(core_cfg);

    if (core_cfg.ext_cv32a60x_supported)
        p.extensions = "cv32a60x";

    p.num_procs  = 64'h1;

    p.misaligned = core_cfg.unaligned_access_supported;

    p.pmpregions_max      = core_cfg.pmp_regions;
    p.pmpregions_writable = core_cfg.pmp_regions;

    p.id_csr_mask = 64'hFFFF_FFFF;
    p.mhartid     = core_cfg.mhartid;
    p.mvendorid   = core_cfg.mvendorid;
    p.marchid     = core_cfg.marchid;
    p.mimpid      = core_cfg.mimpid;

    // Free-running counter CSRs, such as cycle, minstret, and mcycle, are 
    // injected from the DUT. Not predicted by Spike.
    p.csr_counters_injection = 1'b1;

    if (core_cfg.dram_valid) begin
        // CV32E20 firmware is linked against physical DRAM, so DRAM must 
        // cover the ELF load region. A boot ROM at the default 0x10000 would 
        // overlap that region and hijack the bus routing. The reset PC comes
        //  from boot_addr instead.
        p.dram_enable = 1'b1;
        p.dram_base   = core_cfg.dram_base;
        p.dram_size   = core_cfg.dram_size;
        p.bootrom     = 1'b0;
    end
    else begin
        p.dram_enable = 1'b0;
    end

    p.unified_traps = core_cfg.unified_traps;

    // The core's OBI bus services accesses to peripheral addresses (several
    // slaves at 0x1000_0000, 0x1500_0000, 0x2000_0000) that Spike's bus has no
    // device for. Without this, the first store to e.g. the virtual printer
    // raises an access fault in the reference model only, a trap the core never
    // takes, and the two RVFI streams desync. Allowing unmapped accesses makes
    // Spike read zeroes and drop stores, like a bus that accepts the transfer.
    p.allow_unmapped_mem_access = 1'b1;

    // Test-status port: a store of the pass/fail signature sets st_rvfi.halt,
    // so the scoreboard can drop its objection. This is the RVFI end-of-test
    // handshake.
    p.test_status_base = 64'h2000_0000;

    if (core_cfg.boot_addr_valid)
        p.boot_addr = core_cfg.boot_addr;

    if ($value$plusargs("config_file=%s", p.param_file))
        `uvm_info("spike_tandem",
                  $sformatf("Reading Spike parameters from file %s", p.param_file), UVM_LOW)

    return p;
endfunction : rvfi_cfg_to_profile

/**
 * Apply a finished profile and start the model. 
 */
function automatic void rvfi_start_spike(rvfi_spike_profile_t p);
    string binary;

    if (!$value$plusargs("elf_file=%s", binary))
        `uvm_error("spike_tandem", "We need a preloaded binary for tandem verification")

    `uvm_info("spike_tandem", $sformatf("Setting up Spike with binary %s...", binary), UVM_LOW)

    rvfi_apply_spike_profile(p, p.hart_id);

    `uvm_info("spike_tandem", $sformatf("core_name: %s", p.profile_name), UVM_LOW)
    `uvm_info("spike_tandem", $sformatf("boot_addr: 0x%08h", p.boot_addr), UVM_LOW)
    `uvm_info("spike_tandem", $sformatf("isa: '%s'", p.isa), UVM_LOW)

    spike_create(binary);
endfunction : rvfi_start_spike

function automatic void rvfi_initialize_spike(string core_name, st_core_cntrl_cfg core_cfg);
    rvfi_start_spike(rvfi_cfg_to_profile(core_name, core_cfg));
endfunction : rvfi_initialize_spike

`endif
