module uart_tx(
    input wire       clk,
    input wire       reset,
    input wire       start,
    input wire [7:0] data_in,

    output reg tx,
    output reg busy,
    output reg done
);

reg [1:0] state;
parameter IDLE = 0,START=1,DATA=2,STOP=3;
reg [2:0] idx;

wire [1:0] bitdone;
reg counter_start;
counter clk_count(clk,counter_start,reset,bitdone);
reg [7:0] reg_data;

always @(posedge clk) begin
    if (reset) begin
        state <= IDLE;                                                                                      
        idx <= '0;
        tx <= 1'b1;
        busy <= '0;
        done <= '0;
        counter_start<=1'b0;
        reg_data <= '0;
    end
    else begin
        case(state)
            IDLE: begin
                done <= '0;
                busy <= '0;
                tx <= 1'b1;
                if (start) begin
                    busy <= 1'b1;
                    counter_start <= 1'b1;
                    reg_data <= data_in;
                    tx <= 1'b0;
                    state <= START;                    
                end
            end
            START: begin
                if (bitdone==2'b1) begin
                    idx <= 3'b0;                    
                    tx <= reg_data[0];
                    state <= DATA;
                end
            end
            DATA: begin
                if (bitdone==2'b1) begin
                    if (idx==3'd7) begin
                        tx <=1'b1;
                        state <=STOP;
                    end else begin
                        tx <= reg_data[idx+1];
                        idx <= idx+3'd1;
                    end
                end           
            end
            STOP: begin
                if (bitdone==2'b1) begin
                    busy <= 1'b0;
                    done <=1'b1;
                    counter_start <= 1'b0;
                    state <= IDLE;
                end
            end
        endcase;
    end
end
                    

endmodule



module uart_rx (
    input  wire       clk,
    input  wire       reset,
    input  wire       rx,

    output reg [7:0]  data_out,
    output reg        data_valid,
    output reg        framing_error
);
reg [1:0] state;
parameter IDLE = 0, START = 1, DATA = 2, STOP = 3;
wire [1:0] bitdone;
reg rx_meta;
reg rx_sync;
reg counter_start;
reg [2:0] idx;
reg [7:0] reg_data;
counter clk_count(clk,counter_start,reset,bitdone);

always @(posedge clk) begin
    if (reset) begin
        state         <= IDLE;
        data_out      <= 8'd0;
        data_valid    <= 1'b0;
        framing_error <= 1'b0;
        counter_start <= 1'b0;
        rx_meta       <= 1'b1;
        rx_sync       <= 1'b1;
        idx           <= 3'd0;
        reg_data      <= 8'd0;
    end else begin
        rx_meta <=rx;
        rx_sync <= rx_meta;
        data_valid <='0;
        framing_error <= '0;
        case(state)
            IDLE: begin
                busy <= 1'b0;
                done <= '0;
                if (!rx_sync) begin
                    busy <= 1'b1;
                    counter_start <= 1'b1;
                    state <= START;
                    end
                end                                
            START: begin
                if (bitdone==2'b10) begin
                    if (!rx_sync) begin
                        idx <= '0;
                        state <= DATA;
                    end else begin
                        counter_start<=1'b0;
                        busy <= 1'b0;
                        state <= IDLE;
                    end
                end                    
            end
            DATA: begin
                if (bitdone==2'b10) begin
                    reg_data[idx] <= rx_sync;
                    if (idx==3'd7) begin
                        state<=STOP;
                    end else begin
                        idx<=idx+1'd1;
                    end
                end
            end
            STOP:begin
                if (bitdone==2'b10) begin
                    if (rx_sync) begin
                        data_out<=reg_data;
                        data_valid<=1'b1;
                    end else begin
                        framing_error<=1'b1;
                    end
                    busy<=1'b0;
                    state<=IDLE;
                    counter_start<=1'b0;
                end
            end
        endcase;
    end
end


endmodule




module counter(
    input clk,
    input start,
    input reset,

    output reg [1:0] done
);
reg [9:0] count;

always @(*) begin
    if (start && (count==10'd433))
        done = 2'b1;
    else if (start && (count==10'd216))
        done = 2'b10;
    else
        done = '0;
end

always @(posedge clk) begin
    if (reset)
        count <= 10'd0;
    else if (!start || count==10'd433)
        count <= 10'd0;
    else
        count <= count+1'b1;
end



endmodule

