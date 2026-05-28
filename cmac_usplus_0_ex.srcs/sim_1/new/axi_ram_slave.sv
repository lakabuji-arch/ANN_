`timescale 1ps / 1ps

// Simple AXI4 slave memory for simulation
// 256-bit data width, supports INCR bursts, 128KB storage
module axi_ram_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 256,
    parameter DEPTH      = 4096  // 4096 × 256bit = 128KB
) (
    input  wire                 aclk,
    input  wire                 aresetn,

    // Write address channel
    input  wire [ADDR_WIDTH-1:0] awaddr,
    input  wire [7:0]            awlen,
    input  wire [2:0]            awsize,
    input  wire [1:0]            awburst,
    input  wire                  awvalid,
    output wire                  awready,

    // Write data channel
    input  wire [DATA_WIDTH-1:0] wdata,
    input  wire [DATA_WIDTH/8-1:0] wstrb,
    input  wire                  wlast,
    input  wire                  wvalid,
    output wire                  wready,

    // Write response channel
    output wire [1:0]            bresp,
    output wire                  bvalid,
    input  wire                  bready,

    // Read address channel
    input  wire [ADDR_WIDTH-1:0] araddr,
    input  wire [7:0]            arlen,
    input  wire [2:0]            arsize,
    input  wire [1:0]            arburst,
    input  wire                  arvalid,
    output wire                  arready,

    // Read data channel
    output wire [DATA_WIDTH-1:0] rdata,
    output wire [1:0]            rresp,
    output wire                  rlast,
    output wire                  rvalid,
    input  wire                  rready
);

    // Memory array
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    integer init_idx;
    integer wr_byte_idx;

    // Address: use word addressing (lower bits ignored for 256-bit = 32-byte aligned)
    localparam ADDR_SHIFT = $clog2(DATA_WIDTH/8); // 5 for 256-bit

    initial begin
        for (init_idx = 0; init_idx < DEPTH; init_idx = init_idx + 1) begin
            mem[init_idx] = {DATA_WIDTH{1'b0}};
        end
    end

    // =========================================================================
    // Write channel
    // =========================================================================
    reg [ADDR_WIDTH-1:0] wr_addr;
    reg [7:0]            wr_count;
    reg [1:0]            wr_burst;
    reg                  wr_active;

    wire [ADDR_WIDTH-1:0] wr_next_addr = wr_addr + (1 << ADDR_SHIFT);
    wire [ADDR_WIDTH-1:0] wr_word_addr = wr_addr[ADDR_WIDTH-1:ADDR_SHIFT];

    assign awready = !wr_active;
    assign wready  = wr_active;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wr_active <= 1'b0;
            wr_addr   <= 0;
            wr_count  <= 0;
            wr_burst  <= 0;
        end else begin
            if (awvalid && awready) begin
                if (awaddr[31:16] == 16'h0006) begin
                    $display("  [MEM-AW %0t ns] ADDR=0x%h AWLEN=%0d AWSIZE=%0d AWBURST=0x%0h",
                             $time/1000,
                             awaddr,
                             awlen,
                             awsize,
                             awburst);
                end
                wr_active <= 1'b1;
                wr_addr   <= awaddr;
                wr_count  <= awlen;
                wr_burst  <= awburst;
            end

            if (wr_active && wvalid && wready) begin
                for (wr_byte_idx = 0; wr_byte_idx < DATA_WIDTH/8; wr_byte_idx = wr_byte_idx + 1) begin
                    if (wstrb[wr_byte_idx]) begin
                        mem[wr_word_addr][(wr_byte_idx*8) +: 8] <= wdata[(wr_byte_idx*8) +: 8];
                    end
                end

                if (wr_addr[31:16] == 16'h0006) begin
                    $display("  [MEM-W  %0t ns] ADDR=0x%h WSTRB=0x%h WDATA=0x%h WLAST=%b",
                             $time/1000,
                             wr_addr,
                             wstrb,
                             wdata,
                             wlast);
                end

                if (wr_count == 0 || wlast) begin
                    wr_active <= 1'b0;
                end else begin
                    wr_count <= wr_count - 8'd1;
                    wr_addr  <= (wr_burst == 2'b01) ? wr_next_addr : wr_addr;
                end
            end
        end
    end

    // Write response
    reg        bvalid_r;
    reg [1:0]  bresp_r;

    assign bvalid = bvalid_r;
    assign bresp  = bresp_r;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            bvalid_r <= 1'b0;
            bresp_r  <= 2'b00;
        end else begin
            if (wr_active && wvalid && wready && (wr_count == 0 || wlast)) begin
                bvalid_r <= 1'b1;
                bresp_r  <= 2'b00; // OKAY
            end else if (bvalid_r && bready) begin
                bvalid_r <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Read channel — 2-stage pipeline (AR → BRAM read → R channel)
    // rd_remain = total beats remaining (arlen + 1). rlast asserts when
    // rd_remain == 1 (the last beat is being presented on R channel).
    // =========================================================================
    reg [ADDR_WIDTH-1:0] rd_addr;
    reg [7:0]            rd_remain;  // beats remaining (arlen + 1)
    reg [1:0]            rd_burst;
    reg                  rd_active;

    assign arready = !rd_active;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rd_active <= 1'b0;
            rd_addr   <= 0;
            rd_remain <= 0;
            rd_burst  <= 0;
        end else begin
            if (arvalid && arready) begin
                rd_active <= 1'b1;
                rd_addr   <= araddr;
                rd_remain <= arlen + 8'd1;
                rd_burst  <= arburst;
            end

            if (rd_active && rvalid && rready) begin
                if (rd_remain == 1) begin
                    rd_active <= 1'b0;
                end else begin
                    rd_remain <= rd_remain - 8'd1;
                    rd_addr   <= (rd_burst == 2'b01) ? (rd_addr + (1 << ADDR_SHIFT)) : rd_addr;
                end
            end
        end
    end

    reg [DATA_WIDTH-1:0] rdata_r;
    reg                  rvalid_r;
    reg                  rlast_r;

    wire [ADDR_WIDTH-1:0] rd_word_addr = rd_addr[ADDR_WIDTH-1:ADDR_SHIFT];
    wire [DATA_WIDTH-1:0] rd_mem_data  = mem[rd_word_addr];
    wire                  rd_handshake = rvalid_r && rready;
    wire [ADDR_WIDTH-1:0] rd_next_addr = (rd_burst == 2'b01) ? (rd_addr + (1 << ADDR_SHIFT)) : rd_addr;
    wire [ADDR_WIDTH-1:0] rd_load_addr = rd_handshake ? rd_next_addr : rd_addr;
    wire [7:0]            rd_load_remain = rd_handshake ? (rd_remain - 8'd1) : rd_remain;
    wire                  rd_load_valid = rd_active && (!rvalid_r || (rd_handshake && (rd_remain > 8'd1)));
    wire                  rd_load_last = (rd_load_remain == 8'd1);
    wire [DATA_WIDTH-1:0] rd_load_data = mem[rd_load_addr[ADDR_WIDTH-1:ADDR_SHIFT]];

    assign rdata  = rdata_r;
    assign rresp  = 2'b00;
    assign rvalid = rvalid_r;
    assign rlast  = rlast_r;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rvalid_r <= 1'b0;
            rlast_r  <= 1'b0;
            rdata_r  <= 0;
        end else begin
            // When the current beat is accepted, preload the next address rather
            // than replaying the old one for an extra cycle.
            if (rd_load_valid) begin
                if (rd_load_addr[31:16] == 16'h0006) begin
                    $display("  [MEM-R  %0t ns] ADDR=0x%h RDATA=0x%h RLAST=%b",
                             $time/1000,
                             rd_load_addr,
                             rd_load_data,
                             rd_load_last);
                end
                rdata_r  <= rd_load_data;
                rvalid_r <= 1'b1;
                rlast_r  <= rd_load_last;
            end else if (rd_handshake) begin
                rvalid_r <= 1'b0;
                rlast_r  <= 1'b0;
            end
        end
    end

endmodule
