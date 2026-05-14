module freelist
import rv32i_types::*;
(
    input logic clk, 
    input logic rst, 

    input rename2frlist_t rename2frlist,
    input commit2frlist_t commit2frlist, 

    output frlist2rename_t frlist2rename, 
    output logic frlist_full, 
    output logic frlist_empty, 

    input rob2frlist_t rob2frlist


);


logic [5:0] freelist_fifo [31:0] ;   // speculative 


// commited freelist 

logic [5:0] committed_frlist [31:0] ; // committed freelist

logic [5:0] head, tail ; 

logic [5:0] committed_head, committed_tail ; 

logic committed_frlist_full ; 
 logic committed_frlist_empty ; 


localparam logic  [5:0] freelist_last = 6'd31 ; 

logic [5:0] count ; 


logic allocated_this_cycle;


assign frlist_empty = (count == 6'd0);

assign frlist_full = (count == 6'd32);


always_comb begin
    frlist2rename = '0;
    frlist2rename.alloc_valid = !frlist_empty && !allocated_this_cycle;

    frlist2rename.freelist_head = head ;   // this is the head register before popping ?
    frlist2rename.freelist_tail = tail ; 
    frlist2rename.freelistcount = count ; 
    
    if (!frlist_empty && !allocated_this_cycle) begin
        frlist2rename.new_phy_rd = freelist_fifo[head];   
    end else begin
        frlist2rename.new_phy_rd = 6'd0;
    end
end


always_ff @(posedge clk) begin 
    if(rst) begin 
        // Initialize with P32-P63
        for(integer unsigned i = 0; i < 32; i++) begin 
            freelist_fifo[i] <= 6'(32 + i);
        end

        for(integer unsigned i = 0; i < 32; i++) begin 
            committed_frlist[i] <= 6'(32 + i);
        end
        head <= 6'd0;
        tail <= 6'd0;
        count <= 6'd32; 
        allocated_this_cycle <= 1'b0;


        // committed vars

        committed_head <= 6'd0 ; 
        committed_tail <= 6'd0 ; 
      
        
        
    end 

    else begin 

            if(commit2frlist.free_en) begin 

                    committed_head <= (committed_head == freelist_last) ? 6'd0 : committed_head + 6'd1;
                    committed_frlist[committed_tail] <= commit2frlist.old_phy_rd;
                    committed_tail <= (committed_tail == freelist_last) ? 6'd0 : committed_tail + 6'd1;

                    if (!rob2frlist.valid && !frlist_full) begin
                        freelist_fifo[tail] <= commit2frlist.old_phy_rd;
                        tail <= (tail == freelist_last) ? 6'd0 : tail + 6'd1;
                    end
                end



                if (rob2frlist.valid) begin
                // FLUSH: Restore from committed
                    // freelist_fifo <= committed_frlist;
                    // head <= committed_head;
                    // tail <= committed_tail;
                    // count <= 6'd32;


                    if (commit2frlist.free_en) begin
                        // Manually apply commit to get correct restored state
                        freelist_fifo <= committed_frlist;
                        // Patch in the newly freed register at the new tail position
                        freelist_fifo[committed_tail] <= commit2frlist.old_phy_rd;
                        head <= (committed_head == freelist_last) ? 6'd0 : committed_head + 6'd1;
                        // Tail advances by 1 from current committed_tail
                        tail <= (committed_tail == freelist_last) ? 6'd0 : committed_tail + 6'd1;
                        count <= 6'd32;
                    end else begin
                        // Normal flush: just restore from committed
                        freelist_fifo <= committed_frlist;
                        head <= committed_head;
                        tail <= committed_tail;
                        count <= 6'd32;
                    end
                end
                else begin
                    allocated_this_cycle <= 1'b0;
                    //allocate 
                    if (rename2frlist.alloc_ack && !frlist_empty) begin
                        allocated_this_cycle <= 1'b1;
                        if (head == freelist_last) begin 
                            head <= 6'd0;
                        end
                        else begin 
                            head <= head + 6'd1;
                            
                        end
                    //  count <= count - 6'd1; 
                    end

                    case ({rename2frlist.alloc_ack && !frlist_empty, commit2frlist.free_en && !frlist_full})
                    2'b10: count <= count - 6'd1;  // Alloc only
                    2'b01: count <= count + 6'd1;  // Free only
                    2'b11: count <= count;          // Both (net zero change)
                    default: count <= count;        // Neither
                    endcase

                end



      end
end

endmodule: freelist
