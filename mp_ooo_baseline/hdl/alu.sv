module alu
import rv32i_types::*;
(
  input logic [2:0]   aluop,
  input logic [31:0]  a, b,
  output logic [31:0] aluout
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
    unique case (aluop)
      alu_add: aluout = au +   bu;
      alu_sll: aluout = au <<  bu[4:0];
      alu_sra: aluout = unsigned'(as >>> bu[4:0]);
      alu_sub: aluout = au -   bu;
      alu_xor: aluout = au ^   bu;
      alu_srl: aluout = au >>  bu[4:0];
      alu_or:  aluout = au |   bu;
      alu_and: aluout = au &   bu;
      default: aluout = 'x;
    endcase
  end
endmodule : alu