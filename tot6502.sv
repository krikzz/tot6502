
module tot6502(

	input  clk,
	input  enable,
	input  [7:0]dati,
	output reg[7:0]dato,
	output [15:0]addr,
	output rw,
	input  rst_n,
	input  irq_n,
	input  nmi_n,
	input  rdy
);
	
	
	parameter AM_ABS		= 5'h00;
	parameter AM_ZPG		= 5'h01;
	parameter AM_IND		= 5'h02;
	parameter AM_REL		= 5'h03;
	parameter AM_IMM		= 5'h04;
	parameter AM_IMP_X	= 5'h05;//x cycles operations
	parameter AM_IMP_2	= 5'h06;//2 cycles operations
	parameter AM_ABS_J	= 5'h07;
		
	parameter AM_ABS_X	= 5'h08;
	parameter AM_ABS_Y	= 5'h09;
	parameter AM_ZPG_X	= 5'h0A;
	parameter AM_ZPG_Y	= 5'h0B;
	parameter AM_IND_X	= 5'h0C;
	parameter AM_IND_Y	= 5'h0D;
	
	parameter AM_XXX		= 5'h0F;
	
	parameter IS_OADR		= 0;//operand address output
	parameter IS_WREN 	= 1;//write enable
	parameter IS_WROR	   = 2;//write enable only when operand ready
	parameter IS_EXEC		= 3;//operand fetch complete
	
	//N V 5 B D I Z C
	parameter SR_C			= 0;
	parameter SR_Z			= 1;
	parameter SR_I			= 2;
	parameter SR_D			= 3;
	parameter SR_B			= 4;
	parameter SR_5			= 5;
	parameter SR_V			= 6;
	parameter SR_N			= 7;
	
	parameter VE_NMI		= 4'hA;
	parameter VE_RST		= 4'hC;
	parameter VE_IRQ		= 4'hE;
	
	reg [7:0]a, x, y, sr, sp;
	reg [15:0]pc;
	reg [15:0]oaddr;
	
	reg [7:0]inst;
	reg [2:0]tctr;
	reg [7:0]tmp;
	reg [4:0]is;
	reg pb;//page boundery
	reg [1:0]nmi_st;
	reg [1:0]nmi_tg;
	reg [1:0]irq_st;
	reg [3:0]brk_addr;
	reg brk_flag;
	reg nmi_n_st;
	
	
	wire [2:0]ia = inst[7:5];
	wire [2:0]ib = inst[4:2];
	wire [1:0]ic = inst[1:0];
	
	
	//C0
	//(branches)
	wire i_bra		= ib == 4 & ic == 0;////bpl,bmi,bvc,bvs,bcc,bcs,bne,beq
	wire i_jmp_ind	= inst == 8'h6C;
	wire i_jmp_abs	= inst == 8'h4C;
	wire i_jsr		= inst == 8'h20;
	wire i_rts		= inst == 8'h60;
	wire i_rti		= inst == 8'h40;
	wire i_brk		= inst == 8'h00;////brk,irq,nmi
	//(stack)
	wire i_php		= inst == 8'h08;
	wire i_pha		= inst == 8'h48;
	wire i_plp		= inst == 8'h28;
	wire i_pla		= inst == 8'h68;
	//(flags)
	wire i_clc		= inst == 8'h18;
	wire i_cld		= inst == 8'hD8;
	wire i_cli		= inst == 8'h58;
	wire i_clv		= inst == 8'hB8;
	wire i_sec		= inst == 8'h38;
	wire i_sed		= inst == 8'hF8;
	wire i_sei		= inst == 8'h78;
	//index regs
	wire i_bit		= inst == 8'h24 | inst == 8'h2C;
	wire i_sty		= ia == 4 & ic == 0 & ib[0];
	wire i_dey		= inst == 8'h88;
	wire i_tya		= inst == 8'h98;
	wire i_shy		= inst == 8'h9C;
	wire i_shx		= inst == 8'h9E;
	wire i_tay		= inst == 8'hA8;
	wire i_ldy		= ia == 5 & ic == 0 & (ib[0] | ib == 0);
	wire i_iny		= inst == 8'hC8;
	wire i_cpy 		= ia == 6 & ic == 0 & (ib == 0 | ib == 1 | ib == 3);
	wire i_cpx 		= ia == 7 & ic == 0 & (ib == 0 | ib == 1 | ib == 3);
	wire i_inx		= inst == 8'hE8;
	//A0
	wire i_ora		= ia == 0 & ic[0];
	wire i_asl_a	= ia == 0 & ic[1] & ib == 2;
	wire i_asl_m	= ia == 0 & ic[1] & ib != 2;
	//A1
	wire i_and 		= ia == 1 & ic[0];
	wire i_rol_a	= ia == 1 & ic[1] & ib == 2;
	wire i_rol_m	= ia == 1 & ic[1] & ib != 2;
	//A2
	wire i_eor		= ia == 2 & ic[0];
	wire i_lsr_a	= ia == 2 & ic[1] & ib == 2;
	wire i_lsr_m	= ia == 2 & ic[1] & ib != 2;
	//A3
	wire i_adc		= ia == 3 & ic[0];
	wire i_ror_a	= ia == 3 & ic[1] & ib == 2;
	wire i_ror_m	= ia == 3 & ic[1] & ib != 2;
	//A4
	wire i_sta		= ia == 4 & ic[0];
	wire i_stx		= ia == 4 & ic[1] & ib != 2 & ib != 6;
	wire i_txa		= inst == 8'h8A;
	wire i_txs		= inst == 8'h9A;
	//A5
	wire i_lda		= ia == 5 & ic[0];
	wire i_ldx		= ia == 5 & ic[1] & ib != 2 & ib != 6;
	wire i_tax		= ia == 5 & ic[1] & ib == 2;
	wire i_tsx		= ia == 5 & ic[1] & ib == 6;
	//A6
	wire i_cmp 		= ia == 6 & ic[0];//ic == 1;
	wire i_dex		= ia == 6 & ic[1] & ib == 2;
	wire i_dec		= ia == 6 & ic[1] & ib != 2;
	//A7
	wire i_sbc		= ia == 7 & ic[0];
	wire i_inc		= ia == 7 & ic[1] & ib != 2;
	
	

	
	wire [3:0]amode /*synthesis keep*/;
	assign amode[3:0] =
	
	ib == 0 & ic == 0 & ia    == 1	? AM_ABS_J ://jsr abs
	ib == 0 & ic == 0 & ia[2] == 0	? AM_IMP_X :
	ib == 0 & ic == 0 & ia[2] == 1	? AM_IMM   :
	ib == 0 & ic[0] 	   				? AM_IND_X ://(ic 1, 3)
	ib == 0				   				? AM_IMM   ://(ic 2)
	
	ib == 1 		    						? AM_ZPG   ://zpg		
	
	ib == 2 & ic == 0 & ia[2] == 0 	? AM_IMP_X :
	ib == 2 & ic == 0 & ia[2] == 1 	? AM_IMP_2 :
	ib == 2 & ic[0] 				 		? AM_IMM   ://(ic 1,3)
	ib == 2									? AM_IMP_2 ://(ic 2)
		
	ib == 3 & ic == 0 & ia    == 3   ? AM_IND   ://ind (jmp)
	ib == 3 			 						? AM_ABS   ://abs		
	
	ib == 4 & ic == 0 				 	? AM_REL   :
	ib == 4				 				 	? AM_IND_Y :
	
	ib == 5 & ic[1] & ia[2:1] == 2   ? AM_ZPG_Y :
	ib == 5   								? AM_ZPG_X :
	
	ib == 6 & ic[0] == 0					? AM_IMP_2 ://(ic 0, 2)
	ib == 6 									? AM_ABS_Y ://(ic 1, 3)
	
	ib == 7 & ic[1] & ia[2:1] == 2   ? AM_ABS_Y :
	ib == 7   								? AM_ABS_X :
	
	AM_XXX;
	
	
	
	wire long_abs_xy	= tctr < 6 & ic == 3 & (amode == AM_ABS_X | amode == AM_ABS_Y);
	wire long_ind_xy	= tctr < 7 & ic == 3 & (ib == 0 | ib == 4) & (ia != 4 & ia != 5);// & !(ib == 4 & ia == 7)
	wire op_rdy 		= is[IS_EXEC] | (amode == AM_IMM & tctr == 1);//operand fetch complete
	
	/*
	reg op_rdy;
	always @(posedge clk)
	begin
		op_rdy <= is[IS_EXEC] | (amode == AM_IMM & tctr == 1);
	end*/
//*********************************************************************** branches stuff
	wire bra	= 
	ia == 0 ? (sr[SR_N] == 0) : //bpl
	ia == 1 ? (sr[SR_N] != 0) : //bmi
	ia == 2 ? (sr[SR_V] == 0) : //bvc
	ia == 3 ? (sr[SR_V] != 0) : //bvs
	ia == 4 ? (sr[SR_C] == 0) : //bcc
	ia == 5 ? (sr[SR_C] != 0) : //bcs
	ia == 6 ? (sr[SR_Z] == 0) : //bne
				 (sr[SR_Z] != 0) ; //beq

				 
	wire [8:0]bra_val = pc[7:0] + tmp[7:0];
	wire bra_pb			= bra_val[8] ^ tmp[7];//pc page boundery
	
//*********************************************************************** load and modify
	//load and modify inst
	wire ldm_c3		= ic[0] & ib != 2;//illegal op
	wire ldm_act	= ic[1] & (ib[0] | ldm_c3) & ia != 4 & ia != 5;
	
	//load and modufy wr enable
	wire ldm_wre =	
	amode == AM_ZPG 	? tctr == 2 :
	amode == AM_ABS_X ? tctr == 4 :
	amode == AM_ABS_Y ? tctr == 4 : //illegal op
	amode == AM_IND_X ? tctr == 5 : //illegal op
	amode == AM_IND_Y ? tctr == 5 : //illegal op
	tctr == 3;//AM_ZPG_X or  AM_ABS
	
	//load and modufy data latch
	wire ldm_dle =	
	amode == AM_ZPG 	? tctr == 3 : 
	amode == AM_ABS_X ? tctr == 5 :
	amode == AM_ABS_Y ? tctr == 5 : //illegal op
	amode == AM_IND_X ? tctr == 6 : //illegal op
	amode == AM_IND_Y ? tctr == 6 : //illegal op
	tctr == 4;//AM_ZPG_X or  AM_ABS
	
//*********************************************************************** instructions end ctrl		

	//load and modify end
	wire op_end_ldm = 
	amode == AM_ZPG 	? tctr >= 4 : 
	amode == AM_ABS_X ? tctr >= 6 :
	amode == AM_ABS_Y ? tctr >= 6 : //illegal op
	amode == AM_IND_X ? tctr == 7 : //illegal op
	amode == AM_IND_Y ? tctr == 7 : //illegal op
	tctr == 5;//AM_ZPG_X or  AM_ABS

	wire op_end_sta = 
	amode == AM_IND_Y ? tctr >= 5 : 
	amode == AM_ABS_Y ? tctr >= 4 :
	amode == AM_ABS_X ? tctr >= 4 : 
	op_rdy;
	
	
	wire op_end_bra 	= tctr >= (bra == 0 ? 1 : bra_pb ? 3 : 2);
	
	
	wire op_end = 
	ldm_act				? op_end_ldm :
	i_bra 				? op_end_bra : //group of branch ops
	i_sta 				? op_end_sta :
	i_shy					? tctr >= 4 :
	i_shx					? tctr >= 4 :
	amode == AM_IMP_2 ? tctr >= 1 :
	i_pha	| i_php		? tctr >= 2 : 
	i_jmp_abs			? tctr >= 2 : //jmp abs
	i_pla | i_plp		? tctr >= 3 : 
	i_jmp_ind			? tctr >= 4 : //jmp ind
	i_jsr					? tctr >= 5 :
	i_rti					? tctr >= 5 :	
	i_rts					? tctr >= 5 :
	i_brk					? tctr >= 6 :
	op_rdy;
	
	
//***********************************************************************
	
	wire [7:0]operand = ic[1] & ib != 2 ? dato[7:0] : dati[7:0];//dato for i_xxx_m
	
	wire [7:0]inc_val = dato[7:0] + 1;
	wire [7:0]dec_val = dato[7:0] - 1;
	wire [8:0]adc_val = a[7:0] + operand[7:0] + sr[SR_C];
	wire [8:0]sbc_val = a[7:0] + (operand[7:0] ^ 8'hff) + sr[SR_C];
	wire [7:0]ora_val = a[7:0] | operand[7:0];
	wire [7:0]and_val = a[7:0] & operand[7:0];
	wire [7:0]eor_val = a[7:0] ^ operand[7:0];
	wire [7:0]dex_val = x[7:0] - 1;
	wire [7:0]inx_val = x[7:0] + 1;
	wire [7:0]dey_val = y[7:0] - 1;
	wire [7:0]iny_val = y[7:0] + 1;
	
	wire [7:0]cmp_val = operand[7:0];
	wire [7:0]sbx_val = (a[7:0] & x[7:0]) - dati[7:0];
//***********************************************************************		
	
	wire nmi_req 		= nmi_tg[0] != nmi_tg[1];
	wire irq_req 		= irq_st[1] == 0 & sr[SR_I] == 0;
	wire ie_req  		= nmi_req | irq_req;
	wire wr_cycle		= !rw;//not sure if rdy working this way for write cycles
	
	assign addr[15:0] = is[IS_OADR] ? oaddr[15:0] : pc[15:0];
	assign rw 			= !(is[IS_WREN] | (is[IS_WROR] & op_end));
		
	
	//proper delay for nmi. Battletoads sensitive to this stuff
	always @(posedge clk)
	if(enable)
	begin
		nmi_n_st <= nmi_n;
	end
	
	always @(posedge clk)
	if(!rst_n)
	begin
	
		inst 			<= 8'h00;//brk
		brk_addr		<= VE_RST;
		sr				<= (1 << SR_5) | (1 << SR_B);
		tctr 	   	<= 1;
		nmi_tg		<= 0;
		nmi_st		<= 0;
		brk_flag		<= 0;
		is				<= 0;
		
	end
		else
	if(enable & (rdy | wr_cycle))
	begin

//*********************************************************************** interrupts detector	
		nmi_st[1:0] <= {nmi_st[0], nmi_n_st};
		irq_st[1:0] <= {irq_st[0], irq_n};
		
		if(nmi_st[1:0] == 2'b10)
		begin
			nmi_tg[0] <= !nmi_tg[1];
		end
//*********************************************************************** inst fetch/interrupt
		if(tctr == 0 & ie_req)
		begin
		
			inst[7:0] 		<= 8'h00;
			brk_flag			<= 0;
			
			
			if(nmi_req)
			begin
				nmi_tg[1]	<= nmi_tg[0];
				brk_addr		<= VE_NMI;
			end
				else
			begin
				brk_addr		<= VE_IRQ;
			end
			
		end
			else
		if(tctr == 0)
		begin
			inst[7:0] 		<= dati[7:0];
			pc[15:0] 		<= pc + 1;
			brk_flag			<= 1;
			brk_addr			<= VE_IRQ;
		end
//*********************************************************************** ind 			
		if(amode == AM_IND_X)
		case(tctr)
			1:begin
				oaddr[15:8]		<= 0;
				oaddr[7:0]  	<= dati[7:0];// + x[7:0];
				pc 				<= pc + 1;
				is[IS_OADR] 	<= 1;
			end
			2:begin
				oaddr[7:0]		<= oaddr[7:0] + x[7:0];
			end
			3:begin
				tmp[7:0]			<= dati[7:0];
				oaddr[7:0] 		<= oaddr[7:0] + 1;
			end
			4:begin
				oaddr[15:0]		<= {dati[7:0], tmp[7:0]};
				is[IS_EXEC] 	<= 1;
			end
		endcase
		
		
		if(amode == AM_IND_Y)
		case(tctr)
			1:begin
				oaddr[15:0]  	<= {8'h00, dati[7:0]};
				pc 				<= pc + 1;
				is[IS_OADR] 	<= 1;
			end
			2:begin
				{pb, tmp[7:0]}	<= dati[7:0] + y[7:0];
				oaddr[7:0] 		<= oaddr[7:0] + 1;
			end
			3:begin
				oaddr[15:0]		<= {dati[7:0], tmp[7:0]};
				is[IS_EXEC] 	<= !pb;
			end
			4:if(pb == 1)begin
				oaddr[15:8]		<= oaddr[15:8] + 1;
				is[IS_EXEC] 	<= 1;
			end
		endcase
//*********************************************************************** imm
		if(amode == AM_IMM & tctr == 1)
		begin
			pc <= pc + 1;
		end
		
//*********************************************************************** abs
		if(amode == AM_ABS)
		case(tctr)
			1:begin
				tmp[7:0]  		<= dati[7:0];
				pc 				<= pc + 1;
			end
			2:begin
				oaddr[15:0]  	<= {dati[7:0], tmp[7:0]};
				pc 				<= pc + 1;
				is[IS_OADR] 	<= 1;
				is[IS_EXEC] 	<= 1;
			end
		endcase
		
		
		if(amode == AM_ABS_X | amode == AM_ABS_Y)
		case(tctr)
			1:begin
				{pb, tmp[7:0]}	<= dati[7:0] + (amode == AM_ABS_X ? x[7:0] : y[7:0]);
				pc 				<= pc + 1;
			end
			2:begin
				oaddr[15:0]  	<= {dati[7:0], tmp[7:0]};
				pc 				<= pc + 1;
				is[IS_OADR] 	<= 1;
				is[IS_EXEC] 	<= !pb;
			end
			3:if(pb == 1)begin
				oaddr[15:8]		<= oaddr[15:8] + 1;
				is[IS_EXEC] 	<= 1;
			end
		endcase
//*********************************************************************** zpg
		if(amode == AM_ZPG)
		case(tctr)
			1:begin
				oaddr[15:0]  	<= {8'h00, dati[7:0]};
				pc 				<= pc + 1;
				is[IS_OADR] 	<= 1;
				is[IS_EXEC] 	<= 1;
			end
		endcase
		
		
		if(amode == AM_ZPG_X | amode == AM_ZPG_Y)
		case(tctr)
			1:begin
				oaddr[15:0]  	<= {8'h00, dati[7:0]};
				pc 				<= pc + 1;
				is[IS_OADR] 	<= 1;
			end
			2:begin
				oaddr[7:0]		<= oaddr[7:0] + (amode == AM_ZPG_X ? x[7:0] : y[7:0]);
				is[IS_EXEC] 	<= 1;
			end
		endcase
//*********************************************************************** rel
		if(amode == AM_REL & tctr == 1)
		begin
			pc 					<= pc + 1;
		end	
//*********************************************************************** load and modify
		if(ldm_act & ldm_wre)
		begin

			dato[7:0]	<= dati[7:0];
			is[IS_WREN] <= 1;

		end
//*********************************************************************** instructions
//***********************************************************************		
//***********************************************************************		
//*********************************************************************** branch
		
		//the only cmd in this mode
		if(i_jmp_ind)
		case(tctr)
			1:begin
				oaddr[7:0]  	<= dati[7:0];
				pc 				<= pc + 1;
			end
			2:begin
				oaddr[15:8] 	<= dati[7:0];
				is[IS_OADR] 	<= 1;
			end
			3:begin
				oaddr[7:0] 		<= oaddr[7:0] + 1;
				tmp[7:0] 		<= dati[7:0];
			end
			4:begin
				pc[15:0]			<= {dati[7:0], tmp[7:0]};
			end
		endcase
		
		
		if(i_jmp_abs & tctr == 2)
		begin
			pc[15:0]				<= {dati[7:0], tmp[7:0]};
		end
			
		
		if(i_jsr)
		case(tctr)
			1:begin
				//a-lo
				tmp[7:0]			<= dati[7:0];
				pc 				<= pc + 1;
				oaddr[15:0]		<= {8'h01, sp[7:0]};
				is[IS_OADR] 	<= 1;
			end
			2:begin
				dato[7:0]		<= pc[15:8];
				is[IS_WREN]		<= 1;
			end
			3:begin
				dato[7:0]		<= pc[7:0];
				oaddr[7:0]		<= oaddr[7:0]-1;
			end
			4:begin
				oaddr[7:0]		<= oaddr[7:0]-1;
				is[IS_WREN]		<= 0;
				is[IS_OADR] 	<= 0;
			end
			5:begin
				pc[15:0]			<= {dati[7:0], tmp[7:0]};
				sp[7:0]			<= oaddr[7:0];
			end
		endcase
		
		
		if(i_rts)
		case(tctr)
			1:begin
				oaddr[15:0]		<= {8'h01, sp[7:0]};
				is[IS_OADR] 	<= 1;
			end
			2:begin
				oaddr[7:0]		<= oaddr[7:0] + 1;
			end
			3:begin
				tmp[7:0]			<= dati[7:0];
				oaddr[7:0]		<= oaddr[7:0] + 1;
				sp[7:0]			<= oaddr[7:0] + 1;
			end
			4:begin
				pc[15:0]			<= {dati[7:0], tmp[7:0]};
				is[IS_OADR] 	<= 0;
			end
			5:begin
				pc 				<= pc + 1;
			end
		endcase
		
		
		
		if(i_rti)
		case(tctr)
			1:begin
				oaddr[15:0]		<= {8'h01, sp[7:0]};
				is[IS_OADR] 	<= 1;
			end
			2:begin
				oaddr[7:0]		<= oaddr[7:0] + 1;
			end
			3:begin
				sr[7:0]			<= {dati[7:6], sr[5:4], dati[3:0]};
				oaddr[7:0]		<= oaddr[7:0] + 1;
			end
			4:begin
				tmp[7:0]			<= dati[7:0];
				oaddr[7:0]		<= oaddr[7:0] + 1;
				sp[7:0]			<= oaddr[7:0] + 1;
			end
			5:begin
				pc[15:0]			<= {dati[7:0], tmp[7:0]};
			end
		endcase
		
		
		//bpl,bmi,bvc,bvs,bcc,bcs,bne,beq
		if(i_bra)
		case(tctr)
			1:begin
				pc				<= pc + 1;
				tmp[7:0]		<= dati[7:0];
			end
			2:begin
				pc[7:0]		<= bra_val[7:0];
			end
			3:begin
				pc[15:8]		<= tmp[7] ? pc[15:8] - 1 : pc[15:8] + 1;
			end
		endcase
		
		//brk,irq,nmi
		if(i_brk)
		case(tctr)
			1:begin
			
				if(brk_flag)
				begin
					pc 			<=  pc+1;
					dato[7:0]	<= (pc+1) >> 8;
				end
					else
				begin
					dato[7:0]	<= pc[15:8];
				end
				
				oaddr[15:0]		<= {8'h01, sp[7:0]};
				
				is[IS_OADR] 	<= 1;
				is[IS_WREN]		<= brk_addr == VE_RST ? 0 : 1;
			end
			2:begin
				dato[7:0]		<= pc[7:0];
				oaddr[7:0]		<= oaddr[7:0]-1;
			end
			3:begin
				dato[7:0]		<= {sr[7:6], 1'b1, brk_flag, sr[3:0]};
				oaddr[7:0]		<= oaddr[7:0]-1;
				sr[SR_I]			<= 1;
			end
			4:begin				
				sp[7:0] 			<= oaddr[7:0]-1;
				oaddr[15:0]		<= {12'hfff, brk_addr[3:0]};
				is[IS_WREN]		<= 0;
			end
			5:begin
				tmp[7:0]			<= dati[7:0];
				oaddr[7:0]		<= oaddr[7:0] + 1;
			end
			6:begin
				pc[15:0]			<= {dati[7:0], tmp[7:0]};
			end
		endcase
//*********************************************************************** stack
		//pha, php
		if(i_php | i_pha)
		case(tctr)
			1:begin
				dato[7:0] 		<= (i_pha ? a[7:0] : sr[7:0]);
				oaddr[15:8]		<= 8'h01;
				oaddr[7:0]		<= sp[7:0];
				is[IS_OADR] 	<= 1;
				is[IS_WREN]		<= 1;
			end
			2:begin
				sp[7:0]			<= sp[7:0] - 1;
			end
		endcase 
		

		//pla, plp
		if(i_plp | i_pla)
		case(tctr)
			1:begin
				oaddr[15:8]		<= 8'h01;
				oaddr[7:0]		<= sp[7:0];
				is[IS_OADR] 	<= 1;
			end
			2:begin
				sp[7:0]			<= sp[7:0] + 1;
				oaddr[7:0]		<= oaddr[7:0] + 1;
			end
			3:begin
			
				if(i_pla)
				begin
					a[7:0]		<= dati[7:0];
					sr[SR_Z] 	<= dati[7:0] == 0;
					sr[SR_N] 	<= dati[7];
				end
					else
				begin
					 sr[7:0] 	<= {dati[7:6], sr[5:4], dati[3:0]};
				end
				
			end
		endcase 		
//*********************************************************************** status	flags	
		if(i_clc & tctr == 1)//clc
		begin
			sr[SR_C] <= 0;
		end
		
		if(i_cld & tctr == 1)//cld
		begin
			sr[SR_D] <= 0;
		end
		
		if(i_cli & tctr == 1)//cli
		begin
			sr[SR_I] <= 0;
		end
		
		if(i_clv & tctr == 1)//clv
		begin
			sr[SR_V] <= 0;
		end
		
		if(i_sec & tctr == 1)//sec
		begin
			sr[SR_C] <= 1;
		end
		
		if(i_sed & tctr == 1)//sed
		begin
			sr[SR_D] <= 1;
		end
		
		if(i_sei & tctr == 1)//sei
		begin
			sr[SR_I] <= 1;
		end
//*********************************************************************** C0
//****** bit
		if(i_bit & op_rdy)
		begin
			sr[SR_Z] 	<= (dati[7:0] & a[7:0]) == 0;
			sr[SR_V] 	<= dati[6];
			sr[SR_N] 	<= dati[7];
		end
//****** sty
		if(i_sty & tctr == 1)
		begin
			dato[7:0] 	<= y[7:0];
			is[IS_WROR]	<= 1;
		end
//****** dey
		if(i_dey & tctr == 1)
		begin
			y[7:0]		<= dey_val[7:0];
			sr[SR_Z] 	<= dey_val[7:0] == 0;
			sr[SR_N] 	<= dey_val[7];
		end
//****** tya
		if(i_tya & tctr == 1)
		begin
			a[7:0] 		<= y[7:0];
			sr[SR_Z] 	<= y[7:0] == 0;
			sr[SR_N] 	<= y[7];
		end
//****** SHY
		if(i_shy & tctr == 3)
		begin
			dato[7:0] 	<= y[7:0] & (oaddr[15:8] + 1);
			oaddr[15:8] <= y[7:0] & (oaddr[15:8] + 1);
			is[IS_WROR]	<= 1;
		end
//****** SHX		
		if(i_shx & tctr == 3)
		begin
			dato[7:0] 	<= x[7:0] & (oaddr[15:8] + 1);
			oaddr[15:8] <= x[7:0] & (oaddr[15:8] + 1);
			is[IS_WROR]	<= 1;
		end
//****** tay
		if(i_tay & tctr == 1)
		begin
			y[7:0] 		<= a[7:0];
			sr[SR_Z] 	<= a[7:0] == 0;
			sr[SR_N] 	<= a[7];
		end
//****** ldy
		if(i_ldy & op_rdy)
		begin
			y[7:0] 		<= dati[7:0];
			sr[SR_Z] 	<= dati[7:0] == 0;
			sr[SR_N] 	<= dati[7];
		end

//****** iny
		if(i_iny & tctr == 1)
		begin
			y[7:0]		<= iny_val[7:0];
			sr[SR_Z] 	<= iny_val[7:0] == 0;
			sr[SR_N] 	<= iny_val[7];
		end
//****** cpy		
		if(i_cpy & op_rdy)
		begin
			sr[SR_Z] 	<= y[7:0] == dati[7:0];
			sr[SR_C] 	<= y[7:0] >= dati[7:0];
			sr[SR_N] 	<= (y[7:0] - dati[7:0]) >> 7;
		end
//****** cpx		
		if(i_cpx & op_rdy)
		begin
			sr[SR_Z] 	<= x[7:0] == dati[7:0];
			sr[SR_C] 	<= x[7:0] >= dati[7:0];
			sr[SR_N] 	<= (x[7:0] - dati[7:0]) >> 7;
		end
//****** inx
		if(i_inx & tctr == 1)
		begin
			x[7:0]		<= inx_val[7:0];
			sr[SR_Z] 	<= inx_val[7:0] == 0;
			sr[SR_N] 	<= inx_val[7];
		end	
//*********************************************************************** A0 	
//****** ora
		if(i_ora & op_end)
		begin
			a[7:0]		<= ora_val[7:0];
			sr[SR_Z] 	<= ora_val[7:0] == 0;
			sr[SR_N] 	<= ora_val[7];
		end
//****** asl-a
		if(i_asl_a & tctr == 1)
		begin
			a[7:0] 		<= a[7:0] << 1;
			sr[SR_C]		<= a[7];
			sr[SR_Z] 	<= a[6:0] == 0;
			sr[SR_N] 	<= a[6];
		end
//****** asl-m
		if(i_asl_m & ldm_dle)
		begin
			dato[7:0] 	<= dato[7:0] << 1;
			sr[SR_C]		<= dato[7];
			sr[SR_Z] 	<= dato[6:0] == 0;
			sr[SR_N] 	<= dato[6];
		end
//*********************************************************************** A1
//****** and
		if(i_and & op_end)
		begin
			a[7:0]		<= and_val[7:0];
			sr[SR_Z] 	<= and_val[7:0] == 0;
			sr[SR_N] 	<= and_val[7];
		end
//****** rol-a
		if(i_rol_a & tctr == 1)
		begin
			a[7:0] 		<= {a[6:0], sr[SR_C]};
			sr[SR_C]		<= a[7];
			sr[SR_Z] 	<= {a[6:0], sr[SR_C]} == 0;
			sr[SR_N] 	<= a[6];
		end
//****** rol-m
		if(i_rol_m & ldm_dle)
		begin
			dato[7:0]	<= {dato[6:0], sr[SR_C]};
			sr[SR_C]		<= dato[7];
			sr[SR_Z] 	<= {dato[6:0], sr[SR_C]} == 0;
			sr[SR_N] 	<= dato[6];
		end	
//****** ANC
		if(((i_ora & i_asl_a) | (i_and & i_rol_a)) & op_rdy)
		begin
			a[7:0]		<= and_val[7:0];
			sr[SR_C]		<= and_val[7];
			sr[SR_Z] 	<= and_val[7:0] == 0;
			sr[SR_N] 	<= and_val[7];
		end
//*********************************************************************** A2
//****** eor
		if(i_eor & op_end)
		begin
			a[7:0]		<= eor_val[7:0];
			sr[SR_Z] 	<= eor_val[7:0] == 0;
			sr[SR_N] 	<= eor_val[7];
		end			
		
//****** lsr-a
		if(i_lsr_a & tctr == 1)
		begin
			a[7:0] 		<= a[7:0] >> 1;
			sr[SR_C]		<= a[0];
			sr[SR_Z] 	<= a[7:1] == 0;
			sr[SR_N] 	<= 0;
		end
//****** lsr-m
		if(i_lsr_m & ldm_dle)
		begin
			dato[7:0] 	<= dato[7:0] >> 1;
			sr[SR_C]		<= dato[0];
			sr[SR_Z] 	<= dato[7:1] == 0;
			sr[SR_N] 	<= 0;
		end
//****** ALR
		if(i_eor & i_lsr_a & op_rdy)
		begin
			a[7:0]		<= and_val[7:0] >> 1;
			sr[SR_C]		<= and_val[0];
			sr[SR_Z] 	<= and_val[7:1] == 0;
			sr[SR_N] 	<= 0;
		end			
//*********************************************************************** A3		
//****** adc
		if(i_adc & op_end)
		begin
			a[7:0]		<= adc_val[7:0];
			sr[SR_Z] 	<= adc_val[7:0] == 0;
			sr[SR_N] 	<= adc_val[7];
			sr[SR_C]		<= adc_val[8];
			sr[SR_V]		<= (a[7] != adc_val[7]) & (dati[7] != adc_val[7]);
		end
//****** ror-a
		if(i_ror_a & tctr == 1)
		begin
			a[7:0] 		<= {sr[SR_C], a[7:1]};
			sr[SR_C]		<= a[0];
			sr[SR_Z] 	<= {sr[SR_C], a[7:1]} == 0;
			sr[SR_N] 	<= sr[SR_C];
		end
//****** ror-m
		if(i_ror_m & ldm_dle)
		begin
			dato[7:0] 	<= {sr[SR_C], dato[7:1]};
			sr[SR_C]		<= dato[0];
			sr[SR_Z] 	<= {sr[SR_C], dato[7:1]} == 0;
			sr[SR_N] 	<= sr[SR_C];
		end
//****** ARR
		if(i_adc & i_ror_a & op_rdy)
		begin
			a[7:0]		<= {sr[SR_C], and_val[7:1]};
			sr[SR_C]		<= and_val[7];
			sr[SR_Z] 	<= {sr[SR_C], and_val[7:1]} == 0;
			sr[SR_N] 	<= sr[SR_C];
			sr[SR_V]		<= and_val[7] ^ and_val[6];
		end	
//*********************************************************************** A4
//****** sta
		if(i_sta & tctr == 1)
		begin
			dato[7:0] 	<= a[7:0];
			is[IS_WROR]	<= 1;
		end
//****** stx
		if(i_stx & tctr == 1)
		begin
			dato[7:0] 	<= x[7:0];
			is[IS_WROR]	<= 1;
		end
//****** txa
		if(i_txa & tctr == 1)
		begin
			a[7:0] 		<= x[7:0];
			sr[SR_Z] 	<= x[7:0] == 0;
			sr[SR_N] 	<= x[7];
		end
//****** txs
		if(i_txs & tctr == 1)
		begin
			sp[7:0] 		<= x[7:0];
		end
//****** SAX(AAX)
		if(i_sta & i_stx & tctr == 1)
		begin
			dato[7:0] 	<= a[7:0] & x[7:0];
		end		
//*********************************************************************** A5
//****** lda
		if(i_lda & op_rdy)
		begin
			a[7:0] 		<= dati[7:0];
			sr[SR_Z] 	<= dati[7:0] == 0;
			sr[SR_N] 	<= dati[7];
		end
//****** ldx
		if(i_ldx & op_rdy)
		begin
			x[7:0] 		<= dati[7:0];
			sr[SR_Z] 	<= dati[7:0] == 0;
			sr[SR_N] 	<= dati[7];
		end
//****** tax
		if(i_tax & tctr == 1)
		begin
			x[7:0] 		<= a[7:0];
			sr[SR_Z] 	<= a[7:0] == 0;
			sr[SR_N] 	<= a[7];
		end
//****** tsx
		if(i_tsx & tctr == 1)
		begin
			x[7:0] 		<= sp[7:0];
			sr[SR_Z] 	<= sp[7:0] == 0;
			sr[SR_N] 	<= sp[7];
		end
//****** LXA(ATX)
		if(i_lda & i_tax & op_rdy)
		begin
			a[7:0] 		<= dati[7:0];
			x[7:0] 		<= dati[7:0];
			sr[SR_Z] 	<= dati[7:0] == 0;
			sr[SR_N] 	<= dati[7];
		end
//*********************************************************************** A6
//****** cmp
		if(i_cmp & op_end)
		begin
			sr[SR_Z] 	<= a[7:0] == cmp_val[7:0];
			sr[SR_C] 	<= a[7:0] >= cmp_val[7:0];
			sr[SR_N] 	<= (a[7:0] - cmp_val[7:0]) >> 7;
		end
//****** dex
		if(i_dex & tctr == 1)
		begin
			x[7:0]		<= dex_val[7:0];
			sr[SR_Z] 	<= dex_val[7:0] == 0;
			sr[SR_N] 	<= dex_val[7];
		end		
//****** dec
		if(i_dec & ldm_dle)
		begin
			dato[7:0]	<= dec_val[7:0];
			sr[SR_Z] 	<= dec_val[7:0] == 0;
			sr[SR_N] 	<= dec_val[7];
		end
//****** SBX(AXS)
		if(i_cmp & i_dex & op_rdy)	
		begin
			x[7:0]		<= sbx_val[7:0];
			sr[SR_Z] 	<= sbx_val[7:0] == 0;
			sr[SR_N] 	<= sbx_val[7];
			sr[SR_C] 	<= (a & x) >= dati[7:0];
		end
//*********************************************************************** A7	
//****** sbc
		if(i_sbc & op_end)
		begin
			a[7:0]		<= sbc_val[7:0];
			sr[SR_Z] 	<= sbc_val[7:0] == 0;
			sr[SR_N] 	<= sbc_val[7];
			sr[SR_C]		<= sbc_val[8];
			sr[SR_V]		<= (a[7] != sbc_val[7]) & (dati[7] == sbc_val[7]);
		end
//****** inc
		if(i_inc & ldm_dle)
		begin
			dato[7:0]	<= inc_val[7:0];
			sr[SR_Z] 	<= inc_val[7:0] == 0;
			sr[SR_N] 	<= inc_val[7];
		end
//***********************************************************************
		//end cycle
		if(op_end)
		begin
			is				<= 0;
			tctr			<= 0;
		end
			else
		if(tctr != 7)
		begin
			tctr <= tctr + 1;
		end
		
		if(is[IS_EXEC] & !op_end)
		begin
			is[IS_EXEC] <= 0;
		end
		
	end
	
	
	

endmodule
