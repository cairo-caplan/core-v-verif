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


`ifndef __UVMC_RVFI_SPIKE_SV__
`define __UVMC_RVFI_SPIKE_SV__

/**
 * Component that implements reference model functionality with Spike
 */


class uvmc_rvfi_spike#(int ILEN=DEFAULT_ILEN,
                                  int XLEN=DEFAULT_XLEN
) extends uvmc_rvfi_reference_model;

   `uvm_component_param_utils(uvmc_rvfi_spike)

   /**
    * Default constructor.
    */
   function new(string name="uvmc_rvfi_spike", uvm_component parent=null);

       super.new(name, parent);

   endfunction : new

   rvfi_spike_profile_t spike_profile;

   /**
    * A core-specific subclass or refine_profile() overrides this when
    * spike_profile needs values st_core_cntrl_cfg cannot carry.
    */
   virtual function rvfi_spike_profile_t make_profile();
       return rvfi_cfg_to_profile(cfg.core_name, cfg.to_struct());
   endfunction : make_profile

   /**
    * Merge per-core values that st_core_cntrl_cfg cannot express, such as CSR
    * write masks that reproduce the WARL behaviour from the RTL, memory map of
    * the verification bus, and injection knobs.
    */
   virtual function void refine_profile(ref rvfi_spike_profile_t p);
   endfunction : refine_profile

   virtual function void initialize_spike();
       spike_profile = make_profile();
       refine_profile(spike_profile);
       rvfi_start_spike(spike_profile);
   endfunction : initialize_spike

   /**
    * Build phase
    */
   function void build_phase(uvm_phase phase);

       super.build_phase(phase);

       if ($test$plusargs("USE_ISS")) begin
           initialize_spike();
       end
       else begin
           `uvm_info("UVMC_RVFI_SPIKE", "Skipping initialize_spike()", UVM_NONE)
       end
   endfunction : build_phase

   /**
    * Step function - Steps the core and returns a rvfi transaction
    */
   virtual function uvma_rvfi_instr_seq_item_c#(ILEN,XLEN) step (int i, uvma_rvfi_instr_seq_item_c#(ILEN,XLEN) t);

       st_rvfi s_core, s_reference_model;
       uvma_rvfi_instr_seq_item_c#(ILEN,XLEN) t_reference_model;

       s_core = t.seq2rvfi();

       if ($test$plusargs("USE_ISS")) begin
           rvfi_spike_step(s_core, s_reference_model);
       end

       t_reference_model = new("t_reference_model");
       t_reference_model.rvfi2seq(s_reference_model);
       return t_reference_model;

   endfunction : step

endclass : uvmc_rvfi_spike

`endif // __UVMC_RVFI_SPIKE_SV__

