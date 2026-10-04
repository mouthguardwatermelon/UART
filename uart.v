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

wire bitdone;
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
                if (bitdone) begin
                    idx <= 3'b0;
                    tx <= reg_data[0];
                    state <= DATA;
                end
            end
            DATA: begin
                if (bitdone) begin
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
                if (bitdone) begin
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


module counter(
    input clk,
    input start,
    input reset,

    output reg done
);
reg [9:0] count;

assign done = start && (count==10'd433);

always @(posedge clk) begin
    if (reset)
        count <= 10'd0;
    else if (!start || done)
        count <= 10'd0;
    else
        count <= count+1'b1;
end



endmodule
