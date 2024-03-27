`ifndef __PIPELINE_SHELL_SV__
`define __PIPELINE_SHELL_SV__


typedef struct packed {
    st_rvfi rvfi;
    logic valid;
} pipe_stage_t;

module if_stage
    import iss_wrap_pkg::*;
    (
        input logic clk,
        input logic rst_n,
        input logic step, 

        output pipe_stage_t if_id_pipe_o
    );

    always_ff @(posedge clk) begin
        if(step) begin
            if_id_pipe_o.rvfi <= iss_step();
            if_id_pipe_o.valid <= 1'b1;
        end
        else begin
            if_id_pipe_o.rvfi <= if_id_pipe_o.rvfi;
            if_id_pipe_o.valid <= if_id_pipe_o.valid;
        end
    end
endmodule

module id_stage
    import iss_wrap_pkg::*;
    (
        input logic clk,
        input logic rst_n,
        input logic step, 
        input pipe_stage_t pipe_i,

        output pipe_stage_t pipe_o
    );

    always_ff @(posedge clk) begin
        if(step) begin
            pipe_o.rvfi <= pipe_i.rvfi;
            pipe_o.valid <= pipe_i.valid;
        end
        else begin
            pipe_o.rvfi <= pipe_o.rvfi;
            pipe_o.valid <= pipe_o.valid;
        end
    end
endmodule

module ex_stage
    import iss_wrap_pkg::*;
    (
        input logic clk,
        input logic rst_n,
        input logic step, 
        input pipe_stage_t pipe_i,

        output pipe_stage_t pipe_o
    );

    always_ff @(posedge clk) begin
        if(step) begin
            pipe_o.rvfi <= pipe_i.rvfi;
            pipe_o.valid <= pipe_i.valid;
        end
        else begin
            pipe_o.rvfi <= pipe_o.rvfi;
            pipe_o.valid <= 1'b0; //Only output valid at first valid clock cycle
        end
    end
endmodule

module wb_stage
    import iss_wrap_pkg::*;
    (
        input logic clk,
        input logic rst_n,
        input logic step, 
        input pipe_stage_t pipe_i,

        output pipe_stage_t pipe_o
    );

    assign pipe_o.rvfi = pipe_i.rvfi;
    assign pipe_o.valid = pipe_i.valid;

endmodule

module controller
    (
        input logic clk, 
        input logic rst_n,
        input logic valid,

        input pipe_stage_t if_id_pipe_i,
        input pipe_stage_t id_ex_pipe_i,
        input pipe_stage_t ex_wb_pipe_i, 

        output logic if_step_o,
        output logic id_step_o,
        output logic ex_step_o,
        output logic wb_step_o
    );


    int     pipe_count; // Count the number of filled pipeline stages
    logic   step;

    ////////////////////////////////////////////////////////////////////////////
    // STEP CONTROL
    ////////////////////////////////////////////////////////////////////////////

    // Count the amount of filled pipeline stages at the start 
    always_ff @(posedge clk) begin
        if (rst_n == 1'b0)begin 
            pipe_count <= 0;
        end else if (pipe_count < 2) begin
            pipe_count <= pipe_count + 1;
        end else begin
            pipe_count <= pipe_count;
        end
    end

    // step the pipeline until the first stages are filled up to be in sync with the core
    always_comb begin
        if (pipe_count < 2) begin
            step <= 1'b1;
        end
        else if (rvfi_i.rvfi_valid) begin
            step <= 1'b1;
        end
        else begin
            step <= 1'b0;
        end

    end

    assign if_step_o = step;
    assign id_step_o = step;
    assign ex_step_o = step;
    assign wb_step_o = step;






endmodule

module pipeline_shell 
    import uvma_rvfi_pkg::*;
    import iss_wrap_pkg::*;
    (
        uvma_clknrst_if_t clknrst_if,
        uvma_rvfi_instr_if_t rvfi_i,
        uvma_interrupt_if_t interrupt_if_i,
        rvfi_if_t rvfi_o
    );

    pipe_stage_t if_id_pipe;
    pipe_stage_t id_ex_pipe;
    pipe_stage_t ex_wb_pipe;
    pipe_stage_t wb_pipe;
    logic if_step;
    logic id_step;
    logic ex_step;
    logic wb_step;

    controller controller_i(
        .clk            (clknrst_if.clk     ),
        .rst_n          (clknrst_if.reset_n ),
        .valid          (                   ),
        .if_id_pipe_i   (if_id_pipe         ),
        .id_ex_pipe_i   (id_ex_pipe         ),
        .ex_wb_pipe_i   (ex_wb_pipe         ),
        .if_step_o      (if_step            ),
        .id_step_o      (id_step            ),
        .ex_step_o      (ex_step            ),
        .wb_step_o      (wb_step            )

    );

    if_stage if_stage_i(
        .clk            (clknrst_if.clk     ),
        .rst_n          (clknrst_if.reset_n ),
        .step           (if_step            ),
        .if_id_pipe_o   (if_id_pipe         )
        );
    
    id_stage id_stage_i(
        .clk            (clknrst_if.clk     ),
        .rst_n          (clknrst_if.reset_n ),
        .step           (id_step            ),
        .pipe_i         (if_id_pipe         ),
        .pipe_o         (id_ex_pipe         )
    );

    ex_stage ex_stage_i(
        .clk            (clknrst_if.clk     ),
        .rst_n          (clknrst_if.reset_n ),
        .step           (ex_step            ),
        .pipe_i         (id_ex_pipe         ),
        .pipe_o         (ex_wb_pipe         )
    );

    wb_stage wb_stage_i(
        .clk            (clknrst_if.clk     ),
        .rst_n          (clknrst_if.reset_n ),
        .step           (wb_step            ),
        .pipe_i         (ex_wb_pipe         ),
        .pipe_o         (wb_pipe            )
    );



    initial begin
        $display("Pipeline Shell: Starting");
    end

    logic [31:0] irq_drv_ff;



    always_ff @(posedge clknrst_if.clk) begin
        irq_drv_ff <= interrupt_if_i.irq_drv;
        if (irq_drv_ff != interrupt_if_i.irq_drv) begin
            iss_intr(interrupt_if_i.irq_drv);
        end
    end

    always_comb begin
        rvfi_o.clk          <= clknrst_if.clk;
        rvfi_o.valid        <= wb_pipe.valid;
        rvfi_o.order        <= wb_pipe.rvfi.order;
        rvfi_o.insn         <= wb_pipe.rvfi.insn;
        rvfi_o.trap         <= wb_pipe.rvfi.trap;
        rvfi_o.halt         <= wb_pipe.rvfi.halt;
        rvfi_o.dbg          <= wb_pipe.rvfi.dbg;
        rvfi_o.dbg_mode     <= wb_pipe.rvfi.dbg_mode;
        rvfi_o.nmip         <= wb_pipe.rvfi.nmip;
        rvfi_o.intr         <= wb_pipe.rvfi.intr;
        rvfi_o.mode         <= wb_pipe.rvfi.mode;
        rvfi_o.ixl          <= wb_pipe.rvfi.ixl;
        rvfi_o.pc_rdata     <= wb_pipe.rvfi.pc_rdata;
        rvfi_o.pc_wdata     <= wb_pipe.rvfi.pc_wdata;
        rvfi_o.rs1_addr     <= wb_pipe.rvfi.rs1_addr;
        rvfi_o.rs1_rdata    <= wb_pipe.rvfi.rs1_rdata;
        rvfi_o.rs2_addr     <= wb_pipe.rvfi.rs2_addr;
        rvfi_o.rs2_rdata    <= wb_pipe.rvfi.rs2_rdata;
        rvfi_o.rs3_addr     <= wb_pipe.rvfi.rs3_addr;
        rvfi_o.rs3_rdata    <= wb_pipe.rvfi.rs3_rdata;
        rvfi_o.rd1_addr     <= wb_pipe.rvfi.rd1_addr;
        rvfi_o.rd1_wdata    <= wb_pipe.rvfi.rd1_wdata;
        rvfi_o.rd2_addr     <= wb_pipe.rvfi.rd2_addr;
        rvfi_o.rd2_wdata    <= wb_pipe.rvfi.rd2_wdata;
        rvfi_o.mem_addr     <= wb_pipe.rvfi.mem_addr;
        rvfi_o.mem_rdata    <= wb_pipe.rvfi.mem_rdata;
        rvfi_o.mem_rmask    <= wb_pipe.rvfi.mem_rmask;
        rvfi_o.mem_wdata    <= wb_pipe.rvfi.mem_wdata;
        rvfi_o.mem_wmask    <= wb_pipe.rvfi.mem_wmask;
    end

endmodule //pipeline_shell

`endif //__PIPELINE_SHELL_SV__
