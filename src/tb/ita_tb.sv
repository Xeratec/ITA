// Copyright 2020 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module ita_tb;

  import ita_package::*;

  timeunit 10ps;
  timeprecision 1ps;

  localparam time CLK_PERIOD          = 2000ps;
  localparam time APPL_DELAY          = 400ps;
  localparam time ACQ_DELAY           = 1600ps;
  localparam unsigned RST_CLK_CYCLES  = 10;
  // Set to 1 to run the simulation without stalls
  localparam unsigned CONT            = `ifdef NO_STALLS `NO_STALLS `else 0 `endif;
  localparam unsigned ITERS           = 1;

  // Stimuli files
  string INPUT_FILES[5] = {"standalone/Q.txt", "standalone/K.txt", "standalone/Wv_0.txt", "standalone/Qp_in_0.txt", "standalone/O_soft_in_0.txt"};
  string ATTENTION_INPUT_FILES[1] = {"standalone/A_stream_soft_in_0.txt"};
  string INPUT_BIAS_FILES[5] = {"standalone/Bq_0.txt", "standalone/Bk_0.txt", "standalone/Bv_0.txt", "", "standalone/Bo_0.txt"};
  string WEIGHT_FILES[5] = {"standalone/Wq_0.txt", "standalone/Wk_0.txt", "standalone/V.txt", "standalone/Kp_in_0.txt", "standalone/Wo_0.txt"};
  string ATTENTION_WEIGHT_FILES[1] = {"standalone/Vp_in_0.txt"};
  string OUTPUT_FILES[5] = {"standalone/Qp_0.txt", "standalone/Kp_0.txt", "standalone/Vp_0.txt", "standalone/A_0.txt", "standalone/Out_soft_0.txt"};
  string ATTENTION_OUTPUT_FILES[2] = {"standalone/A_0.txt", "standalone/O_soft_0.txt"};

  // Parameters
  integer N_PE, M_TILE_LEN;
  integer N_ENTRIES_PER_TILE;
  integer SEQUENCE_LEN, PROJECTION_SPACE, EMBEDDING_SIZE;
  integer N_TILES_SEQUENCE_DIM, N_TILES_EMBEDDING_DIM, N_TILES_PROJECTION_DIM;
  integer N_TILES_LINEAR_PROJECTION, N_TILES_ATTENTION;
  integer N_TILES_LINEAR_OUTPUT;
  integer N_ENTRIES_LINEAR_OUTPUT, N_ENTRIES_PER_PROJECTION_DIM, N_ENTRIES_PER_SEQUENCE_DIM;
  integer N_TILES_INNER_DIM_LINEAR_PROJECTION[5];
  integer N_ATTENTION_TILE_ROWS, N_GROUPS;

  // Signals
  logic         clk, rst_n;
  ctrl_t        ita_ctrl        ;
  logic         inp_valid, inp_ready;
  logic         inp_weight_valid, inp_weight_ready;
  inp_t         inp             ;
  inp_weight_t  inp_weight      ;
  bias_t        inp_bias        ;
  requant_oup_t requant_oup     ;
  requant_oup_t exp_res;
  logic         oup_valid, oup_ready;

  // Variables
  string simdir;
  integer stim_applied;

  initial begin
    N_PE = `ifdef ITA_N `ITA_N `else 16 `endif;
    M_TILE_LEN = `ifdef ITA_M `ITA_M `else 64 `endif;
    SEQUENCE_LEN = `ifdef SEQ_LENGTH `SEQ_LENGTH `else M_TILE_LEN `endif;
    PROJECTION_SPACE = `ifdef PROJ_SPACE `PROJ_SPACE `else M_TILE_LEN `endif;
    EMBEDDING_SIZE = `ifdef EMBED_SIZE `EMBED_SIZE `else M_TILE_LEN `endif;
    simdir = {
      "../../simvectors/data_S",
      $sformatf("%0d", SEQUENCE_LEN),
      "_E",
      $sformatf("%0d", EMBEDDING_SIZE),
      "_P",
      $sformatf("%0d", PROJECTION_SPACE),
      "_H1_B",
      $sformatf("%0d", `ifdef BIAS `BIAS `else 0 `endif)
    };
    N_TILES_SEQUENCE_DIM = SEQUENCE_LEN / M_TILE_LEN;
    N_TILES_EMBEDDING_DIM = EMBEDDING_SIZE / M_TILE_LEN;
    N_TILES_PROJECTION_DIM = PROJECTION_SPACE / M_TILE_LEN;
    N_TILES_LINEAR_PROJECTION = N_TILES_SEQUENCE_DIM * N_TILES_EMBEDDING_DIM * N_TILES_PROJECTION_DIM;
    N_TILES_ATTENTION = N_TILES_SEQUENCE_DIM * N_TILES_PROJECTION_DIM;
    N_ENTRIES_PER_TILE = M_TILE_LEN * M_TILE_LEN / N_PE;
    N_TILES_LINEAR_OUTPUT = N_TILES_SEQUENCE_DIM * N_TILES_PROJECTION_DIM;
    N_ENTRIES_LINEAR_OUTPUT = N_ENTRIES_PER_TILE * N_TILES_LINEAR_OUTPUT;
    N_ENTRIES_PER_PROJECTION_DIM = N_ENTRIES_PER_TILE * N_TILES_PROJECTION_DIM;
    N_ENTRIES_PER_SEQUENCE_DIM = N_ENTRIES_PER_TILE * N_TILES_SEQUENCE_DIM;
    N_ATTENTION_TILE_ROWS = N_TILES_SEQUENCE_DIM;
    N_GROUPS = 2 * N_ATTENTION_TILE_ROWS;
    N_TILES_INNER_DIM_LINEAR_PROJECTION[0] = N_TILES_EMBEDDING_DIM;
    N_TILES_INNER_DIM_LINEAR_PROJECTION[1] = N_TILES_EMBEDDING_DIM;
    N_TILES_INNER_DIM_LINEAR_PROJECTION[2] = N_TILES_EMBEDDING_DIM;
    N_TILES_INNER_DIM_LINEAR_PROJECTION[3] = '0; // Not used, no bias
    N_TILES_INNER_DIM_LINEAR_PROJECTION[4] = N_TILES_PROJECTION_DIM;
  end

  clk_rst_gen #(
    .CLK_PERIOD    (CLK_PERIOD    ),
    .RST_CLK_CYCLES(RST_CLK_CYCLES)
  ) i_clk_rst_gen (
    .clk_o (clk  ),
    .rst_no(rst_n)
  );

  ita dut (
    .clk_i             (clk             ),
    .rst_ni            (rst_n           ),
    .ctrl_i            (ita_ctrl        ),
    .inp_valid_i       (inp_valid       ),
    .inp_ready_o       (inp_ready       ),
    .inp_weight_valid_i(inp_weight_valid),
    .inp_weight_ready_o(inp_weight_ready),
    .inp_bias_valid_i  (inp_valid       ),
    .inp_bias_ready_o  (                ),
    .inp_i             (inp             ),
    .inp_weight_i      (inp_weight      ),
    .inp_bias_i        (inp_bias        ),
    .oup_o             (requant_oup     ),
    .valid_o           (oup_valid       ),
    .ready_i           (oup_ready       ),
    .busy_o            (                )
  );

function automatic integer open_stim_file(string filename);
  integer stim_fd;
  if (filename == "")
    return 0;
  stim_fd = $fopen({simdir,"/",filename}, "r");
  if (stim_fd == 0) begin
    $fatal("[TB] ITA: Could not open %s stim file!", filename);
  end
  return stim_fd;
endfunction

task read_input(input integer fd);
  integer ret_code;
  for (int i = 0; i < M_TILE_LEN; i++) begin
    ret_code = $fscanf(fd, "%d", inp[i]);
  end
endtask

task read_weight(input integer fd);
  integer ret_code;
  for (int i = 0; i < N_PE; i++) begin
    ret_code = $fscanf(fd, "%d", inp_weight[i]);
  end
endtask

task read_exp_resp(input integer fd);
  integer ret_code;
  for (int i = 0; i < N_PE; i++) begin
    ret_code = $fscanf(fd, "%d", exp_res[i]);
  end
endtask

function bit is_last_tile_inner_dim(input integer phase, input integer tile);
  integer tile_inner_dim;
  tile_inner_dim = tile % N_TILES_INNER_DIM_LINEAR_PROJECTION[phase];
  return tile_inner_dim >= N_TILES_INNER_DIM_LINEAR_PROJECTION[phase]-1;
endfunction

function bit is_end_of_tile(input integer tile_entry);
  return tile_entry >= N_ENTRIES_PER_TILE;
endfunction

function bit is_last_group(input integer group);
  return group >= N_GROUPS - 1;
endfunction

function is_last_entry_of_linear_output(input integer tile_entry);
  return tile_entry >= N_ENTRIES_LINEAR_OUTPUT;
endfunction

function bit should_toggle_input(input integer tile_entry, input integer group);
  return is_last_entry_of_linear_output(tile_entry) && !is_last_group(group);
endfunction

task read_bias(input integer stim_fd_bias, input integer phase, input integer tile);
  integer ret_code;
  if (phase == 3) begin
    inp_bias = '0;
    return;
  end
  if (!is_last_tile_inner_dim(phase, tile))
    return;
  for (int j = 0; j < N_PE; j++) begin
    ret_code = $fscanf(stim_fd_bias, "%d\n", inp_bias[j]);
  end
endtask

task reset_tile(inout integer tile, inout integer tile_entry);
  tile_entry = 0;
  tile += 1;
endtask

task automatic toggle_input(inout integer tile_entry, inout integer group, inout bit input_file_index);
  input_file_index = !input_file_index;
  tile_entry = 0;
  group += 1;
endtask

function integer get_random();
    logic value;
    integer ret_code;
      if (CONT)
        return 1;
    ret_code = randomize(value);
    return value;
endfunction

function bit successful_handshake(input logic valid, input logic ready);
  return valid && ready;
endfunction

function bit is_output_group(input bit input_file_index);
    return input_file_index == 0;
endfunction

function bit is_attention_group(input bit input_file_index);
    return input_file_index == 1;
endfunction

function bit did_finish_attention_dot_product(input integer tile_entry);
    return tile_entry >= N_ENTRIES_PER_PROJECTION_DIM;
endfunction

function bit did_finish_output_dot_product(input integer tile_entry);
    return tile_entry >= N_ENTRIES_PER_SEQUENCE_DIM;
endfunction

function bit is_last_entry_of_output_group(input integer input_file_index, input integer tile_entry);
    return is_output_group(input_file_index) && did_finish_output_dot_product(tile_entry);
endfunction

function bit is_last_entry_of_attention_group(input integer input_file_index, input integer tile_entry);
    return is_attention_group(input_file_index) && did_finish_attention_dot_product(tile_entry);
endfunction

function bit should_toggle_output(input bit input_file_index, input integer tile_entry);
    return is_last_entry_of_output_group(input_file_index, tile_entry) || is_last_entry_of_attention_group(input_file_index, tile_entry);
endfunction

task automatic apply_ITA_inputs(input integer phase);
      integer stim_fd_inp_attn[2];
      bit input_file_index = 0;
      // Initialize the valid and ready signals to 1 to read the first value
      logic inp_valid_q = 1'b1;
      logic inp_ready_q = 1'b1;
      bit is_end_of_input;
      integer tile;
      integer tile_entry;
      integer group;
      integer stim_fd_inp;
      integer stim_fd_bias;

      $display("[TB] ITA: Applying inputs in phase %0d at %0t.", phase, $time);

      group = 0;
      tile = 0;
      tile_entry = 0;
      stim_fd_inp = open_stim_file(INPUT_FILES[phase]);
      stim_fd_bias = open_stim_file(INPUT_BIAS_FILES[phase]);
      stim_fd_inp_attn[0] = stim_fd_inp;
      stim_fd_inp_attn[1] = open_stim_file(ATTENTION_INPUT_FILES[0]);
      is_end_of_input = 0;

      while (!is_end_of_input) begin
        @(posedge clk);
        #(APPL_DELAY);
        if (successful_handshake(inp_valid_q, inp_ready_q)) begin
          read_input(stim_fd_inp);
          read_bias(stim_fd_bias, phase, tile);
        end
        inp_valid = get_random();
        #(ACQ_DELAY-APPL_DELAY);
        inp_valid_q = inp_valid;
        inp_ready_q = inp_ready;
        if(successful_handshake(inp_valid, inp_ready)) begin
          tile_entry += 1;
          if (should_toggle_input(tile_entry, group) && phase == 3) begin
            $display("[TB] ITA: Input Switch: tile_entry: %d, group: %d at %t.", tile_entry, group, $time);
            toggle_input(tile_entry, group, input_file_index);
          end
          if (is_end_of_tile(tile_entry) && phase != 3)
            reset_tile(tile, tile_entry);
          stim_fd_inp = stim_fd_inp_attn[input_file_index];
          is_end_of_input = $feof(stim_fd_inp);
        end
      end
      $fclose(stim_fd_inp);
      $fclose(stim_fd_bias);
endtask

task automatic apply_ITA_weights(input integer phase);
    integer stim_fd_weight_attn[2];
    bit input_file_index = 0;
    // Initialize the valid and ready signals to 1 to read the first value
    logic inp_weight_valid_q = 1'b1;
    logic inp_weight_ready_q = 1'b1;
    integer is_end_of_input;
    integer tile;
    integer tile_entry;
    integer group;
    integer stim_fd_weight;

    $display("[TB] ITA: Applying weights in phase %0d at %0t.", phase, $time);

    group = 0;
    tile = 0;
    tile_entry = 0;
    stim_fd_weight = open_stim_file(WEIGHT_FILES[phase]);
    stim_fd_weight_attn[0] = stim_fd_weight;
    stim_fd_weight_attn[1] = open_stim_file(ATTENTION_WEIGHT_FILES[0]);
    is_end_of_input = 0;


    while (!is_end_of_input) begin
      @(posedge clk);
      #(APPL_DELAY);
      if (successful_handshake(inp_weight_valid_q, inp_weight_ready_q)) begin
        read_weight(stim_fd_weight);
      end
      inp_weight_valid = get_random();
      #(ACQ_DELAY-APPL_DELAY);
      inp_weight_valid_q = inp_weight_valid;
      inp_weight_ready_q = inp_weight_ready;
      if (successful_handshake(inp_weight_valid, inp_weight_ready)) begin
        tile_entry += 1;
        if (should_toggle_input(tile_entry, group) && phase == 3) begin
          $display("[TB] ITA: Weight Switch: tile_entry: %0d, group: %0d at %0t.", tile_entry, group, $time);
          toggle_input(tile_entry, group, input_file_index);
        end
        stim_fd_weight = stim_fd_weight_attn[input_file_index];
        is_end_of_input = $feof(stim_fd_weight);
      end
    end
    $fclose(stim_fd_weight);
  endtask

  task apply_ITA_rqs();
    integer stim_fd_rqs;
    integer ret_code, rand_ret_code;

    for (int phase = 0; phase < 3; phase++) begin
      case(phase)
        0 : begin
          stim_fd_rqs = open_stim_file("RQS_MUL.txt");
        end
        1 : begin
          stim_fd_rqs = open_stim_file("RQS_SHIFT.txt");
        end
        2 : begin
          stim_fd_rqs = open_stim_file("RQS_ADD.txt");
        end
      endcase

      case(phase)
        0 : begin
          for (int j = 0; j < 6; j++) begin
            ret_code = $fscanf(stim_fd_rqs, "%d\n", ita_ctrl.eps_mult[j]);
          end
        end
        1 : begin
          for (int j = 0; j < 6; j++) begin
            ret_code = $fscanf(stim_fd_rqs, "%d\n", ita_ctrl.right_shift[j]);
          end
        end
        2 : begin
          for (int j = 0; j < 6; j++) begin
            ret_code = $fscanf(stim_fd_rqs, "%d\n", ita_ctrl.add[j]);
          end
        end
      endcase

      $fclose(stim_fd_rqs);
    end
  endtask

  task automatic check_ITA_outputs(input integer phase);
    integer exp_resp_fd_attn[2];
    bit input_file_index = 0;
    // Initialize the valid and ready signals to 1 to read the first value
    logic oup_valid_q = 1'b1;
    logic oup_ready_q = 1'b1;
    integer is_end_of_input;
    integer tile_entry;
    integer group;
    integer exp_resp_fd;

    $display("[TB] ITA: Checking outputs in phase %d at %t.", phase, $time);

    group = 0;
    tile_entry = 0;
    input_file_index = 0;
    exp_resp_fd = open_stim_file(OUTPUT_FILES[phase]);
    exp_resp_fd_attn[0] = exp_resp_fd;
    exp_resp_fd_attn[1] = open_stim_file(ATTENTION_OUTPUT_FILES[1]);
    is_end_of_input = 0;

    while (!is_end_of_input) begin
      @(posedge clk);
      #(APPL_DELAY);
      if (successful_handshake(oup_valid_q, oup_ready_q))
        read_exp_resp(exp_resp_fd);
      oup_ready = get_random();
      #(ACQ_DELAY-APPL_DELAY);
      oup_valid_q = oup_valid;
      oup_ready_q = oup_ready;
      if (successful_handshake(oup_valid, oup_ready)) begin
        tile_entry += 1;
        if (requant_oup !== exp_res)
          $display("[TB] ITA: Wrong value received %x, instead of %x at %0t.", requant_oup, exp_res, $time);
        if (!is_last_group(group) && phase == 3 && should_toggle_output(input_file_index, tile_entry)) begin
            $display("[TB] ITA: %0d outputs were checked in phase %0d.",tile_entry, phase);
            $display("[TB] ITA: Output Switch: tile_entry: %0d, group: %0d at %0t.", tile_entry, group, $time);
            toggle_input(tile_entry, group, input_file_index);
          end
      exp_resp_fd = exp_resp_fd_attn[input_file_index];
      is_end_of_input = $feof(exp_resp_fd);
      end
    end
    $fclose(exp_resp_fd);
    $display("[TB] ITA: %0d outputs were checked in phase %0d.",tile_entry, phase);
  endtask

  initial begin: input_application_block
    ita_ctrl = '0;
    ita_ctrl.start = 1'b0;
    ita_ctrl.eps_mult   = 1;
    ita_ctrl.right_shift = 8;
    ita_ctrl.add = 0;
    ita_ctrl.lin_tiles = N_TILES_LINEAR_PROJECTION;
    ita_ctrl.attn_tiles = N_TILES_ATTENTION;
    ita_ctrl.tile_e = N_TILES_EMBEDDING_DIM;
    ita_ctrl.tile_p = N_TILES_PROJECTION_DIM;
    ita_ctrl.tile_s = N_TILES_SEQUENCE_DIM;

    inp_valid = 1'b0;
    inp = '0;
    inp_weight = '0;
    inp_bias = '0;
    oup_ready = 1'b0;
    wait (rst_n);

    for (int i = 0; i < ITERS; i++) begin
      @(posedge clk);
      #(APPL_DELAY);
      ita_ctrl.start = 1'b1;
      stim_applied = 1;

      @(posedge clk);
      #(APPL_DELAY);
      ita_ctrl.start = 1'b0;

      for (int phase = 0; phase < 5; phase++) begin
        apply_ITA_inputs(phase);
      end

      @(posedge clk);
      #(APPL_DELAY);
      inp = '0;
      inp_valid = 1'b0;
      #(100*CLK_PERIOD);
    end
  end

  initial begin: weight_application_block
    inp_weight = '0;
    inp_weight_valid = 1'b0;

    wait (rst_n);

    for (int i = 0; i < ITERS; i++) begin
      @(posedge clk);
      #(APPL_DELAY);

      for (int phase = 0; phase < 5; phase++) begin
        apply_ITA_weights(phase);
      end

      @(posedge clk);
      #(APPL_DELAY);
      inp_weight = '0;
      inp_weight_valid = 1'b0;
    end
  end

  initial begin: rqs_application_block
    wait (rst_n);

    for (int i = 0; i < ITERS; i++) begin
      @(posedge clk);
      #(APPL_DELAY);

      apply_ITA_rqs();
    end
  end

  // Check response
  initial begin: checker_block
    wait (stim_applied);

    for (int i = 0; i < ITERS; i++) begin
      @(posedge clk);
      for (int phase = 0; phase < 5; phase++) begin
        check_ITA_outputs(phase);
      end
    end

    #(50*CLK_PERIOD);
    $finish();
  end

endmodule
