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

// Bridge for talking to the Spike tandem ISS:
//
//   - the RVFI data types, st_rvfi, vector_rvfi and union_rvfi, by including
//     uvma_rvfi_tdefs.sv
//   - every import "DPI-C" of the Spike API
//   - rvfi_spike_profile_t and rvfi_apply_spike_profile, turns a configuration
//     into spike_set_param_* calls,
//   - rvfi_spike_step, marshals a retirement instruction into Spike.
//
//
// Lives next to uvma_rvfi_pkg, compiled by uvma_rvfi_pkg.flist, because it owns
// uvma_rvfi_tdefs.sv's types. The RVFI agent, the reference-model component
// and the scoreboard all import them from here, so the whole stack shares one
// st_rvfi type instead of declaring its own copy.

`ifndef __RVFI_SPIKE_DPI_PKG_SV__
`define __RVFI_SPIKE_DPI_PKG_SV__

package rvfi_spike_dpi_pkg;

  `include "uvma_rvfi_constants.sv"
  `include "uvma_rvfi_tdefs.sv"

  //////////////////////////////////////////////////////////////////////////////
  // Spike DPI API, from vendor/riscv/riscv-isa-sim/openhw/common/riscv_dpi.cc
  //////////////////////////////////////////////////////////////////////////////
  import "DPI-C" function void spike_create(string filename);
  import "DPI-C" function void spike_delete();

  import "DPI-C" function void spike_set_default_params(string profile);
  import "DPI-C" function void spike_set_params_from_file(string paramFilePath);
  import "DPI-C" function void spike_set_param_uint64_t(string base, string name,
                                                        longint unsigned value);
  import "DPI-C" function void spike_set_param_str(string base, string name,
                                                   string value);
  import "DPI-C" function void spike_set_param_bool(string base, string name,
                                                    bit value);
  import "DPI-C" function longint unsigned spike_get_param_uint64_t(string base,
                                                                    string name);
  import "DPI-C" function string spike_get_param_str(string base, string name);
  import "DPI-C" function bit spike_get_param_bool(string base, string name);

  import "DPI-C" function void spike_step_svLogic(inout vector_rvfi core,
                                                  inout vector_rvfi reference_model);
  import "DPI-C" function void spike_step_struct(inout st_rvfi core,
                                                 inout st_rvfi reference_model);

  import "DPI-C" function void spike_get_csr(input longint unsigned proc_id,
      input longint unsigned csr_addr, inout longint unsigned value);
  import "DPI-C" function void spike_put_csr(input longint unsigned proc_id,
      input longint unsigned csr_addr, input longint unsigned value);

  //////////////////////////////////////////////////////////////////////////////
  // Spike configuration profile
  //
  // One struct, one applicator, many producers. A UVM environment fills it
  // from st_core_cntrl_cfg, via rvfi_cfg_to_profile in rvfi_spike.sv. A core
  // testbench fills it from compile-time parameters, via the per-core
  // cve2_spike_profile in the CV32E20 DV repository. Everything that is not
  // core-specific keeps the default below, which reproduces what
  // rvfi_initialize_spike used to hardcode.
  //
  // A field is applied unconditionally, with no "unset" encoding, so a producer
  // starts from rvfi_profile_defaults and overrides what it cares about. This
  // mirrors the previous behaviour, where every spike_set_param_* call was
  // unconditional, while keeping the values in one comparable place.
  //////////////////////////////////////////////////////////////////////////////

  typedef struct {
    // The core's own openhw/.../profile.C, handed to
    // spike_set_default_params, and the hart this profile describes.
    string           profile_name;
    int              hart_id;

    // Optional parameter file ("+config_file=<path>"), loaded after the profile.
    // Empty string means none.
    string           param_file;

    // Instruction set and privilege level.
    string           isa;
    string           priv;
    string           extensions;          // empty means none, e.g. "cv32a60x"

    // Simulation topology.
    longint unsigned num_procs;
    bit              max_steps_enabled;   // the DUT, not Spike, ends the run

    // Memory map.
    bit              bootrom;
    bit              dram_enable;
    longint unsigned dram_base;
    longint unsigned dram_size;
    // The core services accesses to peripheral addresses that Spike's bus has
    // no device for. Without this, the first store to e.g. the virtual printer
    // raises a store access fault in the reference model only, and the two
    // RVFI streams desync.
    bit              allow_unmapped_mem_access;
    // Test-status address. A store here ends the test; 0 disables the handshake.
    longint unsigned test_status_base;
    longint unsigned boot_addr;
    bit              misaligned;

    // PMP.
    longint unsigned pmpregions_max;
    longint unsigned pmpregions_writable;

    // Identification CSRs: mask and value.
    longint unsigned id_csr_mask;
    longint unsigned mhartid;
    longint unsigned mvendorid;
    longint unsigned marchid;
    longint unsigned mimpid;

    // CSR reset values and write masks.
    longint unsigned mtvec_mask;
    longint unsigned mtvec_value;
    longint unsigned mtvec_write_mask;
    longint unsigned mstatus_mask;
    longint unsigned mstatus_value;
    longint unsigned mstatus_write_mask;
    longint unsigned tdata1_mask;
    longint unsigned tdata1_value;
    bit              tdata1_we;
    bit              tdata1_we_enable;
    longint unsigned trigger_count;
    bit              tinfo_presence;

    // Behavioural switches.
    bit              interrupts_injection;
    bit              debug_injection;
    bit              unified_traps;
    bit              csr_counters_injection;
    bit              non_standard_interrupts;
  } rvfi_spike_profile_t;

  // Defaults shared by every core. Each value carries the reason for being here.
  function automatic rvfi_spike_profile_t rvfi_profile_defaults();
    rvfi_spike_profile_t p;
    p = '{
      profile_name            : "generic",
      hart_id                 : 0,
      param_file              : "",

      isa                     : "rv64imac",
      priv                    : "M",
      extensions              : "",

      num_procs               : 64'h1,
      max_steps_enabled       : 1'b0,   // the DUT retiring ends the run

      bootrom                 : 1'b0,   // no boot ROM: reset PC comes from boot_addr
      dram_enable             : 1'b1,
      dram_base               : 64'h0,
      dram_size               : 64'h0,
      allow_unmapped_mem_access : 1'b1,
      test_status_base        : 64'h0,  // 0 means no end-of-test signature address
      boot_addr               : 64'h0,
      misaligned              : 1'b0,

      pmpregions_max          : 64'h0,
      pmpregions_writable     : 64'h0,

      id_csr_mask             : 64'hFFFF_FFFF,
      mhartid                 : 64'h0,
      mvendorid               : 64'h0,
      marchid                 : 64'h0,
      mimpid                  : 64'h0,

      mtvec_mask              : 64'hFFFF_FFFF,
      mtvec_value             : 64'h0,
      mtvec_write_mask        : 64'hFFFF_FFFE,  // standard WARL: mode bit 0 is WARL
      mstatus_mask            : 64'hFFFF_FFFF,
      mstatus_value           : 64'h0000_1800,  // MPP = M
      mstatus_write_mask      : 64'hFFFF_FFFF,
      tdata1_mask             : 64'hFFFF_FFFF,
      tdata1_value            : 64'h0,
      tdata1_we               : 1'b0,
      tdata1_we_enable        : 1'b1,
      trigger_count           : 64'h0,
      tinfo_presence          : 1'b0,

      interrupts_injection    : 1'b1,
      debug_injection         : 1'b1,
      unified_traps           : 1'b0,
      csr_counters_injection  : 1'b1,
      non_standard_interrupts : 1'b0
    };
    return p;
  endfunction : rvfi_profile_defaults

  // The only function that talks Spike's parameter language. Each item is
  // written both under "/top/" and under "/top/core/<hart>/". The C++ side
  // reads the per-core path, but the mirror in riscv_dpi.cc and older builds
  //  without it consult /top/. Writing both is what the previous two 
  // implementations each did in their own subset. See docs/Spike_Integration.md.
  function automatic void rvfi_apply_spike_profile(rvfi_spike_profile_t p,
                                                   input int hart_id = -1);
    string base;
    base = (hart_id < 0) ? $sformatf("/top/core/%0d/", p.hart_id)
                         : $sformatf("/top/core/%0d/", hart_id);

    void'(spike_set_default_params(p.profile_name));

    if (p.param_file != "")
      void'(spike_set_params_from_file(p.param_file));

    if (p.boot_addr == 0) begin
      p.boot_addr = spike_get_param_uint64_t(base, "boot_addr");
      if (p.boot_addr == 0)
        p.boot_addr = spike_get_param_uint64_t("/top/cores/", "boot_addr");
    end

    if (p.extensions != "")
      void'(spike_set_param_str(base, "extensions", p.extensions));

    void'(spike_set_param_uint64_t("/top/", "num_procs", p.num_procs));

    void'(spike_set_param_str("/top/", "isa", p.isa));
    void'(spike_set_param_str(base,    "isa", p.isa));
    void'(spike_set_param_str("/top/", "priv", p.priv));
    void'(spike_set_param_str(base,    "priv", p.priv));

    void'(spike_set_param_bool    ("/top/", "bootrom",   p.bootrom));
    void'(spike_set_param_bool    ("/top/", "misaligned", p.misaligned));
    void'(spike_set_param_bool    (base,    "misaligned", p.misaligned));
    void'(spike_set_param_uint64_t(base,    "boot_addr",  p.boot_addr));

    if (p.dram_enable) begin
      void'(spike_set_param_bool    ("/top/", "dram_enable", p.dram_enable));
      void'(spike_set_param_uint64_t("/top/", "dram_base",   p.dram_base));
      void'(spike_set_param_uint64_t("/top/", "dram_size",   p.dram_size));
    end
    void'(spike_set_param_bool(base, "allow_unmapped_mem_access",
                               p.allow_unmapped_mem_access));
    if (p.test_status_base != 0)
      void'(spike_set_param_uint64_t("/top/", "test_status_base", p.test_status_base));

    void'(spike_set_param_uint64_t(base, "pmpregions_max",      p.pmpregions_max));
    void'(spike_set_param_uint64_t(base, "pmpregions_writable", p.pmpregions_writable));

    void'(spike_set_param_uint64_t(base, "mhartid_override_mask",   p.id_csr_mask));
    void'(spike_set_param_uint64_t(base, "mhartid_override_value",  p.mhartid));
    void'(spike_set_param_uint64_t(base, "mvendorid_override_mask", p.id_csr_mask));
    void'(spike_set_param_uint64_t(base, "mvendorid_override_value", p.mvendorid));
    void'(spike_set_param_uint64_t(base, "marchid_override_mask",   p.id_csr_mask));
    void'(spike_set_param_uint64_t(base, "marchid_override_value",  p.marchid));
    void'(spike_set_param_uint64_t(base, "mimpid_override_mask",    p.id_csr_mask));
    void'(spike_set_param_uint64_t(base, "mimpid_override_value",   p.mimpid));

    void'(spike_set_param_uint64_t(base, "mtvec_override_mask",  p.mtvec_mask));
    void'(spike_set_param_uint64_t(base, "mtvec_override_value", p.mtvec_value));
    void'(spike_set_param_uint64_t(base, "mtvec_write_mask",     p.mtvec_write_mask));

    void'(spike_set_param_uint64_t(base, "mstatus_override_mask",  p.mstatus_mask));
    void'(spike_set_param_uint64_t(base, "mstatus_override_value", p.mstatus_value));
    void'(spike_set_param_uint64_t(base, "mstatus_write_mask",     p.mstatus_write_mask));

    void'(spike_set_param_uint64_t(base, "tdata1_override_mask",  p.tdata1_mask));
    void'(spike_set_param_uint64_t(base, "tdata1_override_value", p.tdata1_value));
    void'(spike_set_param_bool    (base, "tdata1_we",             p.tdata1_we));
    void'(spike_set_param_bool    (base, "tdata1_we_enable",      p.tdata1_we_enable));
    void'(spike_set_param_bool    (base, "tinfo_presence",        p.tinfo_presence));
    void'(spike_set_param_uint64_t(base, "trigger_count",         p.trigger_count));

    void'(spike_set_param_bool(base, "interrupts_injection",    p.interrupts_injection));
    void'(spike_set_param_bool(base, "debug_injection",         p.debug_injection));
    void'(spike_set_param_bool(base, "unified_traps",           p.unified_traps));
    void'(spike_set_param_bool(base, "csr_counters_injection",  p.csr_counters_injection));
    void'(spike_set_param_bool(base, "non_standard_interrupts", p.non_standard_interrupts));

    void'(spike_set_param_bool("/top/", "max_steps_enabled", p.max_steps_enabled));
  endfunction : rvfi_apply_spike_profile

  function automatic void rvfi_spike_step(ref st_rvfi s_core,
                                          ref st_rvfi s_reference_model);
    vector_rvfi a_core;
    vector_rvfi a_reference_model;
    union_rvfi  u;

    s_core.csr_addr[12'h300] = 64'h300;

    u.rvfi   = s_core;
    a_core   = u.array;
    a_reference_model = '0;

    spike_step_svLogic(a_core, a_reference_model);

    u.array           = a_reference_model;
    s_reference_model = u.rvfi;
  endfunction : rvfi_spike_step

endpackage : rvfi_spike_dpi_pkg

`endif // __RVFI_SPIKE_DPI_PKG_SV__
