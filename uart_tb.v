`timescale 1ns/1ps

module tb_uart;

    parameter CLKS_PER_BIT = 434;
    parameter CLK_PERIOD   = 20; // 50 MHz
    parameter BIT_TIME     = CLKS_PER_BIT * CLK_PERIOD;

    reg clk;
    reg reset;
    reg start;
    reg [7:0] data_in;

    wire tx;
    wire busy;
    wire done;

    reg manual_mode;
    reg manual_rx;
    wire rx;

    wire [7:0] data_out;
    wire data_valid;
    wire framing_error;

    integer valid_count;
    integer error_count;
    integer done_count;

    reg [7:0] expected_data;
    reg expect_bad_frame;

    reg previous_valid;
    reg previous_error;
    reg previous_done;

    assign rx = manual_mode ? manual_rx : tx;

    uart_tx transmitter (
        .clk(clk),
        .reset(reset),
        .start(start),
        .data_in(data_in),
        .tx(tx),
        .busy(busy),
        .done(done)
    );

    uart_rx receiver (
        .clk(clk),
        .reset(reset),
        .rx(rx),
        .data_out(data_out),
        .data_valid(data_valid),
        .framing_error(framing_error)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    //Simulation stop if task doesnt work
    task fail;
        input [8*160-1:0] message;
        begin
            $display("FAIL at %0t: %0s", $time, message);
            $finish;
        end
    endtask

    // Delaying for reg update
    always @(posedge clk) begin
        #1;

        if (reset) begin
            previous_valid = 1'b0;
            previous_error = 1'b0;
            previous_done  = 1'b0;
        end else begin
            if (data_valid === 1'b1) begin
                if (previous_valid)
                    fail("data_valid lasted more than one clock");

                if (expect_bad_frame)
                    fail("RX accepted a frame with a bad stop bit");

                if (data_out !== expected_data) begin
                    $display("Expected %02h, received %02h",
                             expected_data, data_out);
                    fail("Received byte mismatch");
                end

                valid_count = valid_count + 1;
            end

            if (framing_error === 1'b1) begin
                if (previous_error)
                    fail("framing_error lasted more than one clock");

                if (!expect_bad_frame)
                    fail("Unexpected framing error");

                error_count = error_count + 1;
            end

            if (data_valid && framing_error)
                fail("data_valid and framing_error asserted together");

            if (done === 1'b1) begin
                if (previous_done)
                    fail("TX done lasted more than one clock");

                if (busy !== 1'b0)
                    fail("TX busy was high when done asserted");

                done_count = done_count + 1;
            end

            previous_valid = data_valid;
            previous_error = framing_error;
            previous_done  = done;
        end
    end

    // Data format check
    task check_transmission;
        input [7:0] value;

        reg [9:0] frame;
        reg expected_tx;
        integer symbol;
        integer cycle;
        integer valid_before;
        integer done_before;

        begin
            // start then eight bits then stop
            frame = {1'b1, value, 1'b0};

            valid_before = valid_count;
            done_before = done_count;
            expected_data = value;

            @(negedge clk);
            data_in = value;
            start = 1'b1;

            @(posedge clk);
            #2;

            if (tx !== 1'b0 || busy !== 1'b1)
                fail("TX did not begin the start bit");

            @(negedge clk);
            start = 1'b0;

            data_in = ~value;

            for (symbol = 0; symbol < 10; symbol = symbol + 1) begin
                for (cycle = 1; cycle <= CLKS_PER_BIT;
                     cycle = cycle + 1) begin

                    @(posedge clk);
                    #2;

                    if (cycle < CLKS_PER_BIT)
                        expected_tx = frame[symbol];
                    else if (symbol < 9)
                        expected_tx = frame[symbol + 1];
                    else
                        expected_tx = 1'b1;

                    if (tx !== expected_tx) begin
                        $display(
                            "Byte %02h, symbol %0d, cycle %0d: expected %b, got %b",
                            value, symbol, cycle, expected_tx, tx
                        );
                        fail("Incorrect TX value or bit duration");
                    end

                    if (symbol == 9 && cycle == CLKS_PER_BIT) begin
                        if (done !== 1'b1 || busy !== 1'b0)
                            fail("TX did not finish on the expected edge");
                    end else begin
                        if (busy !== 1'b1 || done !== 1'b0)
                            fail("TX finished too early");
                    end
                end
            end

            repeat (4) @(negedge clk);

            if (valid_count != valid_before + 1)
                fail("Loopback expected exactly one received byte");

            if (done_count != done_before + 1)
                fail("Expected exactly one TX done pulse");

            if (done !== 1'b0)
                fail("TX done did not clear");
        end
    endtask

    task drive_rx_frame;
        input [7:0] value;
        input integer bit_time_ns;
        input bad_stop;

        integer bit_index;
        integer valid_before;
        integer errors_before;
        reg [7:0] previous_data;

        begin
            valid_before = valid_count;
            errors_before = error_count;
            previous_data = data_out;
            expected_data = value;
            expect_bad_frame = bad_stop;

            @(negedge clk);
            #3;

            manual_rx = 1'b0;
            #(bit_time_ns);

            for (bit_index = 0; bit_index < 8;
                 bit_index = bit_index + 1) begin
                manual_rx = value[bit_index];
                #(bit_time_ns);
            end

            manual_rx = !bad_stop;
            #(bit_time_ns);

            manual_rx = 1'b1;
            #(2 * BIT_TIME);

            if (bad_stop) begin
                if (error_count != errors_before + 1)
                    fail("Expected exactly one framing error");

                if (valid_count != valid_before)
                    fail("Bad frame produced data_valid");

                if (data_out !== previous_data)
                    fail("Bad frame changed data_out");
            end else begin
                if (valid_count != valid_before + 1)
                    fail("Independent RX test missed a byte");

                if (error_count != errors_before)
                    fail("Good frame produced a framing error");
            end

            expect_bad_frame = 1'b0;
        end
    endtask

    integer value;
    integer saved_valid;
    integer saved_errors;

    initial begin
        reset = 1'b1;
        start = 1'b0;
        data_in = 8'd0;

        manual_mode = 1'b0;
        manual_rx = 1'b1;

        valid_count = 0;
        error_count = 0;
        done_count = 0;

        expected_data = 8'd0;
        expect_bad_frame = 1'b0;

        previous_valid = 1'b0;
        previous_error = 1'b0;
        previous_done = 1'b0;

        $dumpfile("uart.vcd");
        $dumpvars(0, tb_uart);

        repeat (4) @(negedge clk);

        if (tx !== 1'b1 || busy !== 1'b0 || done !== 1'b0)
            fail("Incorrect TX reset outputs");

        if (data_out !== 8'd0 ||
            data_valid !== 1'b0 || framing_error !== 1'b0)
            fail("Incorrect RX reset outputs");

        reset = 1'b0;
        repeat (6) @(negedge clk);

        $display("Testing all 256 bytes and TX timing");
        for (value = 0; value < 256; value = value + 1)
            check_transmission(value[7:0]);

        manual_mode = 1'b1;
        repeat (6) @(negedge clk);

        $display("Testing RX independently");
        drive_rx_frame(8'hA6, BIT_TIME, 1'b0);

        // Small timing differences between sender and receiver.
        drive_rx_frame(8'h3C, BIT_TIME * 98 / 100, 1'b0);
        drive_rx_frame(8'h81, BIT_TIME * 102 / 100, 1'b0);

        $display("Testing rejection of a short low glitch");
        saved_valid = valid_count;
        saved_errors = error_count;

        @(negedge clk);
        #3;
        manual_rx = 1'b0;
        #(BIT_TIME / 4);
        manual_rx = 1'b1;
        #(12 * BIT_TIME);

        if (valid_count != saved_valid || error_count != saved_errors)
            fail("Short glitch was treated as a frame");

        $display("Testing a bad stop bit and recovery");
        drive_rx_frame(8'h00, BIT_TIME, 1'b1);
        drive_rx_frame(8'h5A, BIT_TIME, 1'b0);

        $display("PASS: all UART checks passed.");
        $finish;
    end

    initial begin
        #100_000_000;
        fail("Timeout: UART did not complete the tests");
    end

endmodule