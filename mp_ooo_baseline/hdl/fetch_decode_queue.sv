module fetch_decode_queue
import rv32i_types::*;
 #(
    parameter QUEUE_SIZE = 32,
    parameter QUEUE_ENTRIES = 8
)(
    input logic clk,
    input logic rst,
    input logic write,
    input logic read,
    input logic [QUEUE_SIZE-1 :0]write_data,
    input logic [QUEUE_SIZE-1 : 0]write_pc,
    output logic [QUEUE_SIZE - 1 : 0]read_data, 
    output logic [QUEUE_SIZE - 1 :0] read_pc,
    output logic filled,
    output logic empty, 

    input branch_flush_t branch_flush
);
    //logic filled ; 
    logic [QUEUE_SIZE -1 :0] data_temp [QUEUE_ENTRIES];
    logic [QUEUE_SIZE -1 : 0 ] pc_temp [QUEUE_ENTRIES];
    logic [3:0] head;
    logic [3:0] tail;

    logic [2:0] head_index, tail_index;

    assign head_index = head[2:0];
    assign tail_index = tail[2:0];


    assign empty = (head == tail) ? 1'b1 : 1'b0;


    assign filled = ((head_index == tail_index) && head[3] != tail[3]) ? 1'b1 :1'b0;

    assign read_data = data_temp[head_index];
    assign read_pc = pc_temp[head_index];

    always_ff @(posedge clk) begin

        if (rst) begin
            head <= '0;
            tail <= '0;

        end 
        else if(branch_flush.valid && branch_flush.branch_taken) begin 

            head <= '0;
            tail <= '0;

        end
        
        
        
        else begin
            if (write && !filled) begin
                data_temp[tail_index] <= write_data;
                pc_temp[tail_index] <= write_pc;
                tail <= tail + 4'd1;
            end 
            if (read && !empty) begin
                head <= head + 4'd1;


            end else begin
                // forced to stall

            end
        


        end
    

    end


endmodule :  fetch_decode_queue