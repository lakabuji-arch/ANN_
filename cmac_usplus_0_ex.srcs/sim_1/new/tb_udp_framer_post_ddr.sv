`timescale 1ns / 1ps

module tb_udp_framer_post_ddr;

    localparam int MAX_BYTES = 1024;
    localparam [47:0] CFG_DEST_MAC  = 48'h10_11_12_13_14_15;
    localparam [47:0] CFG_LOCAL_MAC = 48'h20_21_22_23_24_25;
    localparam [31:0] CFG_LOCAL_IP  = 32'hC0A8010A;
    localparam [31:0] CFG_DEST_IP   = 32'hC0A80114;
    localparam [15:0] CFG_SRC_PORT  = 16'h1234;
    localparam [15:0] CFG_DEST_PORT = 16'h5678;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg [511:0] s_axis_tdata = 512'd0;
    reg [63:0]  s_axis_tkeep = 64'd0;
    reg         s_axis_tvalid = 1'b0;
    reg         s_axis_tlast = 1'b0;
    wire        s_axis_tready;

    reg  [15:0] i_tx_payload_bytes = 16'd0;
    reg         tx_meta_empty = 1'b1;

    wire [511:0] m_axis_tdata;
    wire [63:0]  m_axis_tkeep;
    wire         m_axis_tvalid;
    wire         m_axis_tlast;
    reg          m_axis_tready = 1'b1;
    reg          inject_stalls = 1'b0;

    wire         o_stat_tx_udp;
    wire         o_meta_rd_en;

    integer fail_count = 0;
    integer got_frame_len = 0;
    integer meta_rd_count = 0;
    reg     tx_done = 1'b0;
    integer ready_cycle = 0;

    byte unsigned input_payload [0:MAX_BYTES-1];
    byte unsigned expected_frame[0:MAX_BYTES-1];
    byte unsigned got_frame     [0:MAX_BYTES-1];

    udp_100g_framer_pro dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .s_axis_tdata       (s_axis_tdata),
        .s_axis_tkeep       (s_axis_tkeep),
        .s_axis_tvalid      (s_axis_tvalid),
        .s_axis_tlast       (s_axis_tlast),
        .s_axis_tready      (s_axis_tready),
        .i_tx_payload_bytes (i_tx_payload_bytes),
        .tx_meta_empty      (tx_meta_empty),
        .cfg_dest_mac       (CFG_DEST_MAC),
        .cfg_local_mac      (CFG_LOCAL_MAC),
        .cfg_local_ip       (CFG_LOCAL_IP),
        .cfg_dest_ip        (CFG_DEST_IP),
        .cfg_src_port       (CFG_SRC_PORT),
        .cfg_dest_port      (CFG_DEST_PORT),
        .m_axis_tdata       (m_axis_tdata),
        .m_axis_tkeep       (m_axis_tkeep),
        .m_axis_tvalid      (m_axis_tvalid),
        .m_axis_tlast       (m_axis_tlast),
        .m_axis_tready      (m_axis_tready),
        .o_stat_tx_udp      (o_stat_tx_udp),
        .o_meta_rd_en       (o_meta_rd_en)
    );

    always #5 clk = ~clk;

    function automatic [63:0] keep_mask(input integer byte_count);
        begin
            if (byte_count <= 0) begin
                keep_mask = 64'd0;
            end else if (byte_count >= 64) begin
                keep_mask = 64'hFFFF_FFFF_FFFF_FFFF;
            end else begin
                keep_mask = (64'h1 << byte_count) - 1'b1;
            end
        end
    endfunction

    function automatic [15:0] calc_ip_checksum(input integer payload_len);
        reg [31:0] sum;
        reg [16:0] fold_once;
        reg [16:0] fold_twice;
        begin
            sum = 32'h4500 + (16'd28 + payload_len[15:0]) + 16'h4000 + 16'h4011 +
                  CFG_LOCAL_IP[31:16] + CFG_LOCAL_IP[15:0] + CFG_DEST_IP[31:16] + CFG_DEST_IP[15:0];
            fold_once = sum[15:0] + sum[31:16];
            fold_twice = fold_once[15:0] + fold_once[16];
            calc_ip_checksum = ~fold_twice[15:0];
        end
    endfunction

    task automatic clear_buffers;
        integer idx;
        begin
            for (idx = 0; idx < MAX_BYTES; idx = idx + 1) begin
                input_payload[idx] = 8'h00;
                expected_frame[idx] = 8'h00;
                got_frame[idx] = 8'h00;
            end
            got_frame_len = 0;
            meta_rd_count = 0;
            tx_done = 1'b0;
            tx_meta_empty = 1'b1;
        end
    endtask

    // 在 negedge 切换 ready，避免 testbench 与 DUT 在 posedge 同时改/采样 ready 产生竞态。
    always @(negedge clk) begin
        if (!rst_n) begin
            m_axis_tready <= 1'b1;
            ready_cycle <= 0;
        end else if (!inject_stalls) begin
            m_axis_tready <= 1'b1;
            ready_cycle <= 0;
        end else begin
            ready_cycle <= ready_cycle + 1;
            // 每 7 个周期拉低 2 个周期，稳定制造下游 backpressure。
            case (ready_cycle % 7)
                2, 3: m_axis_tready <= 1'b0;
                default: m_axis_tready <= 1'b1;
            endcase
        end
    end

    task automatic build_expected_frame(input integer payload_len, input integer seed, output integer frame_len);
        integer idx;
        integer raw_frame_len;
        reg [15:0] ip_total_len;
        reg [15:0] udp_total_len;
        reg [15:0] ip_checksum;
        begin
            raw_frame_len = 42 + payload_len;
            frame_len = (raw_frame_len < 60) ? 60 : raw_frame_len;
            ip_total_len = 16'd28 + payload_len[15:0];
            udp_total_len = 16'd8 + payload_len[15:0];
            ip_checksum = calc_ip_checksum(payload_len);

            expected_frame[0]  = CFG_DEST_MAC[47:40];
            expected_frame[1]  = CFG_DEST_MAC[39:32];
            expected_frame[2]  = CFG_DEST_MAC[31:24];
            expected_frame[3]  = CFG_DEST_MAC[23:16];
            expected_frame[4]  = CFG_DEST_MAC[15:8];
            expected_frame[5]  = CFG_DEST_MAC[7:0];
            expected_frame[6]  = CFG_LOCAL_MAC[47:40];
            expected_frame[7]  = CFG_LOCAL_MAC[39:32];
            expected_frame[8]  = CFG_LOCAL_MAC[31:24];
            expected_frame[9]  = CFG_LOCAL_MAC[23:16];
            expected_frame[10] = CFG_LOCAL_MAC[15:8];
            expected_frame[11] = CFG_LOCAL_MAC[7:0];
            expected_frame[12] = 8'h08;
            expected_frame[13] = 8'h00;
            expected_frame[14] = 8'h45;
            expected_frame[15] = 8'h00;
            expected_frame[16] = ip_total_len[15:8];
            expected_frame[17] = ip_total_len[7:0];
            expected_frame[18] = 8'h00;
            expected_frame[19] = 8'h00;
            expected_frame[20] = 8'h40;
            expected_frame[21] = 8'h00;
            expected_frame[22] = 8'h40;
            expected_frame[23] = 8'h11;
            expected_frame[24] = ip_checksum[15:8];
            expected_frame[25] = ip_checksum[7:0];
            expected_frame[26] = CFG_LOCAL_IP[31:24];
            expected_frame[27] = CFG_LOCAL_IP[23:16];
            expected_frame[28] = CFG_LOCAL_IP[15:8];
            expected_frame[29] = CFG_LOCAL_IP[7:0];
            expected_frame[30] = CFG_DEST_IP[31:24];
            expected_frame[31] = CFG_DEST_IP[23:16];
            expected_frame[32] = CFG_DEST_IP[15:8];
            expected_frame[33] = CFG_DEST_IP[7:0];
            expected_frame[34] = CFG_SRC_PORT[15:8];
            expected_frame[35] = CFG_SRC_PORT[7:0];
            expected_frame[36] = CFG_DEST_PORT[15:8];
            expected_frame[37] = CFG_DEST_PORT[7:0];
            expected_frame[38] = udp_total_len[15:8];
            expected_frame[39] = udp_total_len[7:0];
            expected_frame[40] = 8'h00;
            expected_frame[41] = 8'h00;

            for (idx = 0; idx < payload_len; idx = idx + 1) begin
                input_payload[idx] = byte'(seed + idx);
                expected_frame[42 + idx] = input_payload[idx];
            end
        end
    endtask

    task automatic send_payload(input integer payload_len);
        integer offset;
        integer idx;
        integer beat_len;
        reg [511:0] data_word;
        reg [63:0]  keep_word;
        begin
            offset = 0;
            tx_meta_empty = 1'b0;
            while (offset < payload_len) begin
                beat_len = ((payload_len - offset) > 64) ? 64 : (payload_len - offset);
                data_word = 512'd0;
                keep_word = keep_mask(beat_len);
                for (idx = 0; idx < beat_len; idx = idx + 1) begin
                    data_word[idx*8 +: 8] = input_payload[offset + idx];
                end

                @(negedge clk);
                s_axis_tdata = data_word;
                s_axis_tkeep = keep_word;
                s_axis_tvalid = 1'b1;
                s_axis_tlast = ((offset + beat_len) == payload_len);

                do begin
                    @(posedge clk);
                end while (!(s_axis_tvalid && s_axis_tready));

                @(negedge clk);
                s_axis_tdata = 512'd0;
                s_axis_tkeep = 64'd0;
                s_axis_tvalid = 1'b0;
                s_axis_tlast = 1'b0;

                offset = offset + beat_len;
            end
            tx_meta_empty = 1'b1;
        end
    endtask

    task automatic check_frame(input integer payload_len, input integer frame_len, input integer case_id);
        integer idx;
        begin
            if (meta_rd_count != 1) begin
                fail_count = fail_count + 1;
                $error("case %0d: meta read count mismatch, got=%0d expected=1", case_id, meta_rd_count);
            end

            if (got_frame_len != frame_len) begin
                fail_count = fail_count + 1;
                $error("case %0d: output frame length mismatch, got=%0d expected=%0d", case_id, got_frame_len, frame_len);
            end

            for (idx = 0; idx < frame_len; idx = idx + 1) begin
                if (got_frame[idx] != expected_frame[idx]) begin
                    fail_count = fail_count + 1;
                    $error("case %0d: frame byte[%0d] mismatch, got=%02x expected=%02x", case_id, idx, got_frame[idx], expected_frame[idx]);
                    disable check_frame;
                end
            end

            if (fail_count == 0) begin
                $display("[PASS] framer case %0d payload_len=%0d", case_id, payload_len);
            end
        end
    endtask

    task automatic print_frame_summary(input integer payload_len, input integer frame_len, input integer case_id);
        integer idx;
        integer head_len;
        integer tail_start;
        begin
            head_len = (frame_len < 48) ? frame_len : 48;
            tail_start = (frame_len > 16) ? (frame_len - 16) : 0;

            $display("[RESULT] framer case %0d payload_len=%0d frame_len=%0d meta_rd_count=%0d", case_id, payload_len, got_frame_len, meta_rd_count);

            $write("[RESULT] framer case %0d header_plus_data=", case_id);
            for (idx = 0; idx < head_len; idx = idx + 1) begin
                $write("%02x", got_frame[idx]);
                if (idx != (head_len - 1)) begin
                    $write(" ");
                end
            end
            $write("\n");

            if (frame_len > 16) begin
                $write("[RESULT] framer case %0d tail_bytes=", case_id);
                for (idx = tail_start; idx < frame_len; idx = idx + 1) begin
                    $write("%02x", got_frame[idx]);
                    if (idx != (frame_len - 1)) begin
                        $write(" ");
                    end
                end
                $write("\n");
            end
        end
    endtask

    task automatic run_case(input integer payload_len, input integer seed, input integer case_id, input bit use_stalls);
        integer frame_len;
        integer wait_cycles;
        begin
            $display("[RUN ] framer case %0d payload_len=%0d stalls=%0d", case_id, payload_len, use_stalls);
            clear_buffers();
            inject_stalls = use_stalls;
            i_tx_payload_bytes = payload_len[15:0];
            build_expected_frame(payload_len, seed, frame_len);
            send_payload(payload_len);

            wait_cycles = 0;
            while (!tx_done && (wait_cycles < 400)) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end

            if (!tx_done) begin
                fail_count = fail_count + 1;
                $error("case %0d: timeout waiting for framer output", case_id);
            end

            check_frame(payload_len, frame_len, case_id);
            print_frame_summary(payload_len, frame_len, case_id);
            inject_stalls = 1'b0;
            repeat (3) @(posedge clk);
        end
    endtask

    always @(posedge clk) begin
        integer idx;
        integer write_idx;
        if (!rst_n) begin
            got_frame_len <= 0;
            meta_rd_count <= 0;
            tx_done <= 1'b0;
        end else begin
            if (o_meta_rd_en) begin
                meta_rd_count <= meta_rd_count + 1;
            end

            if (m_axis_tvalid && m_axis_tready) begin
                write_idx = got_frame_len;
                for (idx = 0; idx < 64; idx = idx + 1) begin
                    if (m_axis_tkeep[idx]) begin
                        got_frame[write_idx] = m_axis_tdata[idx*8 +: 8];
                        write_idx = write_idx + 1;
                    end
                end
                got_frame_len <= write_idx;
                if (m_axis_tlast) begin
                    tx_done <= 1'b1;
                end
            end
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        run_case(10, 8'h10, 1, 1'b0);
        run_case(50, 8'h40, 2, 1'b0);
        run_case(500, 8'h80, 3, 1'b0);
        run_case(50, 8'h40, 4, 1'b1);
        run_case(500, 8'h80, 5, 1'b1);

        if (fail_count == 0) begin
            $display("[PASS] tb_udp_framer_post_ddr complete");
        end else begin
            $error("[FAIL] tb_udp_framer_post_ddr fail_count=%0d", fail_count);
        end
        $finish;
    end

endmodule