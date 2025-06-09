module pwm (
  input wire clk,
  input wire up,
  input wire down,
  input wire [2:0] state_desired,
  input wire uart_command_valid,
  output reg target_reached,
  output reg [7:0] current_state_msg,
  output wire moving,
  output reg pwm
  );

  parameter size_counter = 25; // size of count vector 
  parameter max_count = 2**25; // max numver in count vector
  parameter cycle_count = 539_999; // 20 ms, 27Mhz
  parameter duty_count = 53_999;// 1.5 ms, 27Mhz

  // parameter cycle_count = 1000; // test cycle
  // parameter duty_count = 300;  // test duty
  
  reg [size_counter:0] prev_count_cycle;
  reg [size_counter:0] count_cycle;
  reg [size_counter:0] count_duty;
  reg [size_counter:0] duty_count_reg;
  reg cycle_flag = 1'b0;
  reg value = 1'b0;
  reg [2:0] state = 3'b001;
  reg up_prev;
  reg down_prev;

  reg [25:0] target_position;
  reg [17:0] increment_timer;     // 18 bits for 135,000 count (5ms at 27MHz)
  reg start_movement;             // Command to start movement
  reg movement_active;            // Status from movement block
  reg uart_command_valid_prev;    // To detect edge
  reg [7:0] current_state_reg;
  

  // Parameters for smooth movement
  localparam auto_increment = 100;              // Step size for smooth movement
  localparam timer_5ms = 135_000;              // 5ms at 27MHz (27,000,000 * 0.005)

  // Position counts
  localparam idle_count = 21_499, // Arm should be at a level for transport
             preload_count = 12_499, // Arm should be at lowest level for loading
             load_count = 21_499, // Same as idle
             delivery_count = 39_499, // Arm should be little less than top
             top_count = 42_999, // Arm is at highest to enter trailer
             increment_count = 1000,
             decrement_count = 1000;

   // 0 idle/load -> i
   // 1 preload -> p
   // 2 load/idle -> l
   // 3 raise -> t
   // 4 unload -> e


  // State definitions
  localparam IDLE = 3'b001,
             PRELOAD = 3'b010,
             LOAD = 3'b011,
             DELIVERY = 3'b100,
             TOP = 3'b101,
             INCREMENT = 3'b110,
             DECREMENT = 3'b111;

  /*
  * State Desired
  * "t" -> top
  * "p" -> preload
  * "i" -> idle/bottom
  * "e" -> delivery
  * "u" -> up
  * "d" -> down
  */

  initial begin // Initializing regs
    prev_count_cycle = { (size_counter+1) {1'b0} };  
    count_cycle = { (size_counter+1) {1'b0} };  
    count_duty = { (size_counter+1) {1'b0} };  
    duty_count_reg = idle_count;
    target_position = idle_count;
    target_reached = 0;
    current_state_reg = "I";
    current_state_msg = current_state_reg;

  end

  assign moving = movement_active;

  // Handle physical button inputs and UART commands
  always @(posedge clk) begin
      up_prev <= up;
      down_prev <= down;
      uart_command_valid_prev <= uart_command_valid;
      start_movement <= 0;  // Reset trigger each cycle
      
      // UART command has priority and works only when not moving
      if (uart_command_valid && !uart_command_valid_prev && !moving) begin
          case (state_desired)
              IDLE: begin
                  target_position <= idle_count;
                  current_state_reg <= "I";
                  start_movement <= 1;
              end
              PRELOAD: begin
                  target_position <= preload_count;
                  current_state_reg <= "P";
                  start_movement <= 1;
              end
              LOAD: begin
                  target_position <= load_count;
                  current_state_reg <= "L";
                  start_movement <= 1;
              end
              DELIVERY: begin
                  target_position <= delivery_count;
                  current_state_reg <= "E";
                  start_movement <= 1;
              end
              TOP: begin
                  target_position <= top_count;
                  current_state_reg <= "T";
                  start_movement <= 1;
              end
              INCREMENT: begin
                  if (target_position + increment_count <= top_count) begin
                      target_position <= target_position + increment_count;
                      current_state_reg <= "U";
                      start_movement <= 1;
                  end
              end
              DECREMENT: begin
                  if (target_position >= preload_count + decrement_count) begin
                      target_position <= target_position - decrement_count;
                      current_state_reg <= "D";
                      start_movement <= 1;
                  end
              end

              default: begin
                  // Invalid state, do nothing
              end
          endcase

      end else if (!moving && !uart_command_valid) begin
      // Physical buttons work only when not moving and no UART command
          if (up && !up_prev) begin
            if (target_position + increment_count <= top_count) begin
                target_position <= target_position + increment_count;
                current_state_reg <= "U";
                start_movement <= 1;
            end
          end

          if (down && !down_prev) begin
            if (target_position >= preload_count + decrement_count) begin
              target_position <= target_position - decrement_count;
              current_state_reg <= "D";
              start_movement <= 1;
            end
          end

      end 

  end // end always

  // Drive pwm smoothly
  always @(posedge clk) begin
      target_reached <= 0;  // Reset reached signal each cycle
      // Start movement when triggered
      if (start_movement) begin
          movement_active <= 1;
          increment_timer <= 0;
      end
      // Handle ongoing movement
      else if (movement_active) begin
          // 5ms timer
          if (increment_timer >= timer_5ms) begin
              increment_timer <= 0;
              
              // Move toward target
              if (duty_count_reg < target_position) begin
                  if ((target_position - duty_count_reg) >= auto_increment) begin
                      duty_count_reg <= duty_count_reg + auto_increment;
                  end else begin
                      duty_count_reg <= target_position;  // Final step to exact target
                      movement_active <= 0;
                      target_reached <= 1;  // Signal that target was reached
                      current_state_msg <= current_state_reg;
                  end
              end else if (duty_count_reg > target_position) begin
                  if ((duty_count_reg - target_position) >= auto_increment) begin
                      duty_count_reg <= duty_count_reg - auto_increment;
                  end else begin
                      duty_count_reg <= target_position;  // Final step to exact target
                      movement_active <= 0;
                      target_reached <= 1;  // Signal that target was reached
                      current_state_msg <= current_state_reg;
                  end
              end else begin
                  movement_active <= 0;  // Already at target
                  target_reached <= 1;   // Signal that target was reached
                  current_state_msg <= current_state_reg;
              end
          end else begin
              increment_timer <= increment_timer + 1;
          end
      end else begin
          increment_timer <= 0;
      end
  end
  
  always @ (posedge clk ) begin // Create cycle
    count_cycle <= count_cycle + 1'b1;
    if ( ( (count_cycle - prev_count_cycle) + max_count ) % max_count >= cycle_count ) begin
      cycle_flag <= 1'b1;
      prev_count_cycle <= count_cycle;
    end else begin
      cycle_flag <= 1'b0;
    end
  end

  always @ (posedge clk) begin // Create duty cycle
    if(cycle_flag) begin 
      count_duty <= { (size_counter+1) {1'b0} };  
    end else begin
      count_duty <= count_duty + 1'b1;
    end

    if (count_duty < duty_count_reg ) begin
      value = 1'b1;
    end else begin
      value = 1'b0;
    end
  end

  always @ ( * ) begin // Assign value to pwm 
    pwm <= value; 
  end

endmodule
