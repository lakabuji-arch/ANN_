`timescale 1ns / 1ps

module tb_udp_deframer_pre_ddr;

    localparam int MAX_BYTES = 1024;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg [511:0] s_axis_tdata = 512'd0;
    reg [63:0]  s_axis_tkeep = 64'd0;
    reg         s_axis_tvalid = 1'b0;
    reg         s_axis_tlast = 1'b0;
    wire        s_axis_tready;

    wire [511:0] m_axis_tdata;
    wire [63:0]  m_axis_tkeep;
    wire         m_axis_tvalid;
    wire         m_axis_tlast;
    reg          m_axis_tready = 1'b1;

    wire         o_payload_cmd_valid;
    wire [15:0]  o_payload_bytes;
    wire         o_stat_rx_udp;

    integer fail_count = 0;
    integer got_payload_len = 0;
    integer payload_cmd_len = 0;
    reg     payload_cmd_seen = 1'b0;
    reg     rx_done = 1'b0;

    byte unsigned expected_frame   [0:MAX_BYTES-1];
    byte unsigned expected_payload [0:MAX_BYTES-1];
    byte unsigned got_payload      [0:MAX_BYTES-1];

    udp_100g_deframer_pro dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .s_axis_tdata        (s_axis_tdata),
        .s_axis_tkeep        (s_axis_tkeep),
        .s_axis_tvalid       (s_axis_tvalid),
        .s_axis_tlast        (s_axis_tlast),
        .s_axis_tready       (s_axis_tready),
        .m_axis_tdata        (m_axis_tdata),
        .m_axis_tkeep        (m_axis_tkeep),
        .m_axis_tvalid       (m_axis_tvalid),
        .m_axis_tlast        (m_axis_tlast),
        .m_axis_tready       (m_axis_tready),
        .o_payload_cmd_valid (o_payload_cmd_valid),
        .o_payload_bytes     (o_payload_bytes),
        .o_stat_rx_udp       (o_stat_rx_udp)
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
                  16'hC0A8 + 16'h010A + 16'hC0A8 + 16'h0114;
            fold_once = sum[15:0] + sum[31:16];
            fold_twice = fold_once[15:0] + fold_once[16];
            calc_ip_checksum = ~fold_twice[15:0];
        end
    endfunction

    task automatic clear_buffers;
        integer idx;
        begin
            for (idx = 0; idx < MAX_BYTES; idx = idx + 1) begin
                expected_frame[idx] = 8'h00;
                expected_payload[idx] = 8'h00;
                got_payload[idx] = 8'h00;
            end
            got_payload_len = 0;
            payload_cmd_len = 0;
            payload_cmd_seen = 1'b0;
            rx_done = 1'b0;
        end
    endtask

    task automatic build_udp_frame(input integer payload_len, input integer seed, output integer frame_len);
        integer idx;
        reg [15:0] ip_total_len;
        reg [15:0] udp_total_len;
        reg [15:0] ip_checksum;
        begin
            frame_len = 42 + payload_len;
            ip_total_len = 16'd28 + payload_len[15:0];
            udp_total_len = 16'd8 + payload_len[15:0];
            ip_checksum = calc_ip_checksum(payload_len);

            expected_frame[0]  = 8'h10;
            expected_frame[1]  = 8'h11;
            expected_frame[2]  = 8'h12;
            expected_frame[3]  = 8'h13;
            expected_frame[4]  = 8'h14;
            expected_frame[5]  = 8'h15;
            expected_frame[6]  = 8'h20;
            expected_frame[7]  = 8'h21;
            expected_frame[8]  = 8'h22;
            expected_frame[9]  = 8'h23;
            expected_frame[10] = 8'h24;
            expected_frame[11] = 8'h25;
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
            expected_frame[26] = 8'hC0;
            expected_frame[27] = 8'hA8;
            expected_frame[28] = 8'h01;
            expected_frame[29] = 8'h0A;
            expected_frame[30] = 8'hC0;
            expected_frame[31] = 8'hA8;
            expected_frame[32] = 8'h01;
            expected_frame[33] = 8'h14;
            expected_frame[34] = 8'h12;
            expected_frame[35] = 8'h34;
            expected_frame[36] = 8'h56;
            expected_frame[37] = 8'h78;
            expected_frame[38] = udp_total_len[15:8];
            expected_frame[39] = udp_total_len[7:0];
            expected_frame[40] = 8'h00;
            expected_frame[41] = 8'h00;

            for (idx = 0; idx < payload_len; idx = idx + 1) begin
                expected_payload[idx] = byte'(seed + idx);
                expected_frame[42 + idx] = expected_payload[idx];
            end
        end
    endtask

    task automatic send_frame(input integer frame_len);
        integer offset;
        integer idx;
        integer beat_len;
        reg [511:0] data_word;
        reg [63:0]  keep_word;
        begin
            offset = 0;
            while (offset < frame_len) begin
                beat_len = ((frame_len - offset) > 64) ? 64 : (frame_len - offset);
                data_word = 512'd0;
                keep_word = keep_mask(beat_len);
                for (idx = 0; idx < beat_len; idx = idx + 1) begin
                    data_word[idx*8 +: 8] = expected_frame[offset + idx];
                end

                @(negedge clk);
                s_axis_tdata = data_word;
                s_axis_tkeep = keep_word;
                s_axis_tvalid = 1'b1;
                s_axis_tlast = ((offset + beat_len) == frame_len);

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
        end
    endtask

    task automatic check_payload(input integer payload_len, input integer case_id);
        integer idx;
        begin
            if (!payload_cmd_seen) begin
                fail_count = fail_count + 1;
                $error("case %0d: o_payload_cmd_valid was not asserted", case_id);
            end else if (payload_cmd_len != payload_len) begin
                fail_count = fail_count + 1;
                $error("case %0d: payload length mismatch, cmd=%0d expected=%0d", case_id, payload_cmd_len, payload_len);
            end

            if (got_payload_len != payload_len) begin
                fail_count = fail_count + 1;
                $error("case %0d: captured payload length mismatch, got=%0d expected=%0d", case_id, got_payload_len, payload_len);
            end

            for (idx = 0; idx < payload_len; idx = idx + 1) begin
                if (got_payload[idx] != expected_payload[idx]) begin
                    fail_count = fail_count + 1;
                    $error("case %0d: payload byte[%0d] mismatch, got=%02x expected=%02x", case_id, idx, got_payload[idx], expected_payload[idx]);
                    disable check_payload;
                end
            end

            if (fail_count == 0) begin
                $display("[PASS] deframer case %0d payload_len=%0d", case_id, payload_len);
            end
        end
    endtask

    task automatic print_payload_summary(input integer payload_len, input integer case_id);
        integer idx;
        integer tail_start;
        integer preview_len;
        begin
            preview_len = (payload_len < 16) ? payload_len : 16;
            tail_start = (payload_len > 16) ? (payload_len - 16) : 0;

            $display("[RESULT] deframer case %0d payload_len=%0d cmd_len=%0d captured_len=%0d", case_id, payload_len, payload_cmd_len, got_payload_len);

            $write("[RESULT] deframer case %0d first_bytes=", case_id);
            for (idx = 0; idx < preview_len; idx = idx + 1) begin
                $write("%02x", got_payload[idx]);
                if (idx != (preview_len - 1)) begin
                    $write(" ");
                end
            end
            $write("\n");

            if (payload_len > 16) begin
                $write("[RESULT] deframer case %0d last_bytes=", case_id);
                for (idx = tail_start; idx < payload_len; idx = idx + 1) begin
                    $write("%02x", got_payload[idx]);
                    if (idx != (payload_len - 1)) begin
                        $write(" ");
                    end
                end
                $write("\n");
            end
        end
    endtask

    task automatic run_case(input integer payload_len, input integer seed, input integer case_id);
        integer frame_len;
        integer wait_cycles;
        begin
            $display("[RUN ] deframer case %0d payload_len=%0d", case_id, payload_len);
            clear_buffers();
            build_udp_frame(payload_len, seed, frame_len);
            send_frame(frame_len);

            wait_cycles = 0;
            while (!rx_done && (wait_cycles < 200)) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end

            if (!rx_done) begin
                fail_count = fail_count + 1;
                $error("case %0d: timeout waiting for deframer output", case_id);
            end

            check_payload(payload_len, case_id);
            print_payload_summary(payload_len, case_id);
            repeat (3) @(posedge clk);
        end
    endtask

    always @(posedge clk) begin
        integer idx;
        integer write_idx;
        if (!rst_n) begin
            got_payload_len <= 0;
            payload_cmd_len <= 0;
            payload_cmd_seen <= 1'b0;
            rx_done <= 1'b0;
        end else begin
            if (o_payload_cmd_valid) begin
                payload_cmd_len <= o_payload_bytes;
                payload_cmd_seen <= 1'b1;
            end

            if (m_axis_tvalid && m_axis_tready) begin
                write_idx = got_payload_len;
                for (idx = 0; idx < 64; idx = idx + 1) begin
                    if (m_axis_tkeep[idx]) begin
                        got_payload[write_idx] = m_axis_tdata[idx*8 +: 8];
                        write_idx = write_idx + 1;
                    end
                end
                got_payload_len <= write_idx;
                if (m_axis_tlast) begin
                    rx_done <= 1'b1;
                end
            end
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        run_case(10, 8'h10, 1);
        run_case(50, 8'h40, 2);
        run_case(500, 8'h80, 3);

        if (fail_count == 0) begin
            $display("[PASS] tb_udp_deframer_pre_ddr complete");
        end else begin
            $error("[FAIL] tb_udp_deframer_pre_ddr fail_count=%0d", fail_count);
        end
        $finish;
    end

endmodule