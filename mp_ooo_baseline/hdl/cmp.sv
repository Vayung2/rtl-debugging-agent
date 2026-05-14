module cmp
import rv32i_types::*;
(
  input logic [2:0]  cmpop,
  input logic [31:0] a,
  input logic [31:0] b,
  output logic       cmpout
);

  logic signed   [31:0] as;
  logic signed   [31:0] bs;
  logic unsigned [31:0] au;
  logic unsigned [31:0] bu;

  assign as =   signed'(a);
  assign bs =   signed'(b);
  assign au = unsigned'(a);
  assign bu = unsigned'(b);

  always_comb begin
    unique case (cmpop)
      beq:  cmpout = (au == bu);
      bne:  cmpout = (au != bu);
      blt:  cmpout = (as <  bs);
      bge:  cmpout = (as >=  bs);
      bltu: cmpout = (au <  bu);
      bgeu: cmpout = (au >=  bu);
      default: cmpout = 1'bx;
    endcase
  end
endmodule: cmp