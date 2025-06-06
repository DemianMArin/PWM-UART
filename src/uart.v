module uart (
    input clk,         // 27MHz clock
    input rx,          // UART RX from external device
    input target_reached,  // Signal from PWM when target is reached
    input [7:0] current_state_msg,  // Fixed: should be 8-bit input
    output tx,         // UART TX to external device
    output reg [2:0] state_desired,  // State for PWM
    output reg command_valid         // Valid command signal for PWM
);

    // Reset generation
    reg reset_n = 0;
    reg [7:0] reset_counter = 0;
    
    always @(posedge clk) begin
        if (reset_counter < 100) begin
            reset_counter <= reset_counter + 1;
            reset_n <= 0;
        end else begin
            reset_n <= 1;
        end
    end
    
    // UART signals
    reg tx_en;                 // Transmit enable
    reg [2:0] waddr;           // Write address
    reg [7:0] wdata;           // Write data
    reg rx_en;                 // Receive enable
    reg [2:0] raddr;           // Read address
    wire [7:0] rdata;          // Read data
    wire rx_rdy_n;             // Receive ready (active low)
    wire tx_rdy_n;             // Transmit ready (active low)
    
    // State machine for transmitting responses
    reg [2:0] tx_state;
    // Modified: Use 2 bits to handle 3 types of pending transmissions
    reg [1:0] tx_pending;      // 0=none, 1=ACK, 2=REACHED, 3=STATE_UPDATE
    
    // State machine for receiving data
    reg [3:0] rx_state;
    
    // State definitions
    localparam IDLE = 3'b001,
               PRELOAD = 3'b010,
               DELIVERY = 3'b011,
               TOP = 3'b100,
               INCREMENT = 3'b101,
               DECREMENT = 3'b110;

    // Periodic state update timer
    localparam timer_100ms = 2700000;  // 100ms at 27MHz
    reg [21:0] timer_count_reg;        // Reduced size - 22 bits is enough for 2.7M
    
    // Target reached edge detection
    reg target_reached_prev;
   
    // Initialize registers
    initial begin
        tx_en = 0;
        rx_en = 0;
        waddr = 0;
        raddr = 0;
        tx_state = 0;
        tx_pending = 0;
        rx_state = 0;
        state_desired = IDLE;
        command_valid = 0;
        timer_count_reg = 0;
    end
    
    // UART Master instance
    UART_MASTER_Top uart_master(
        .I_CLK(clk),              // Input clock (27MHz)
        .I_RESETN(reset_n),       // Reset signal (active low)
        .I_TX_EN(tx_en),          // Transmit enable
        .I_WADDR(waddr),          // Write address
        .I_WDATA(wdata),          // Write data
        .I_RX_EN(rx_en),          // Receive enable
        .I_RADDR(raddr),          // Read address
        .O_RDATA(rdata),          // Read data
        .SIN(rx),                 // Serial input (RX)
        .RxRDYn(rx_rdy_n),        // Receive ready (active low)
        .SOUT(tx),                // Serial output (TX)
        .TxRDYn(tx_rdy_n),        // Transmit ready (active low)
        .DDIS(),                  // Not used
        .INTR(),                  // Interrupt (not used)
        .DCDn(1'b1),              // Data Carrier Detect (not used, tie high)
        .CTSn(1'b1),              // Clear To Send (not used, tie high)
        .DSRn(1'b1),              // Data Set Ready (not used, tie high)
        .RIn(1'b1),               // Ring Indicator (not used, tie high)
        .DTRn(),                  // Data Terminal Ready (not used)
        .RTSn()                   // Request To Send (not used)
    );
    
    always @(posedge clk) begin
        if (!reset_n) begin
            timer_count_reg <= 0;
            tx_pending <= 0;
            target_reached_prev <= 0;
        end else begin
            
            // 100ms timer for periodic state updates
            if (timer_count_reg >= timer_100ms) begin
                timer_count_reg <= 0;
                // Queue periodic state update if no other transmission is pending
                if (tx_pending == 0) begin
                    tx_pending <= 2'b11;  // STATE_UPDATE
                end
                // Note: If another transmission is pending, we skip this cycle
                // The next 100ms timer will try again
            end else begin
                timer_count_reg <= timer_count_reg + 1;
            end

            // Detect target reached edge and queue "R" response
            target_reached_prev <= target_reached;
            if (target_reached && !target_reached_prev) begin
                // Priority: REACHED response has higher priority than periodic updates
                if (tx_pending == 0 || tx_pending == 2'b11) begin
                    tx_pending <= 2'b10; // REACHED response
                end
            end

            // Transmit state machine
            case (tx_state)
                0: begin  // Idle state, check for pending transmissions
                    if (tx_pending != 0 && !tx_rdy_n) begin
                        tx_state <= 1;
                    end
                end
                
                1: begin  // Send response based on pending type
                    case (tx_pending)
                        2'b01: wdata <= "A";                    // ACK
                        2'b10: wdata <= "R";                    // REACHED
                        2'b11: wdata <= current_state_msg;      // STATE_UPDATE
                        default: wdata <= "?";                  // Should not happen
                    endcase

                    waddr <= 3'b000;  // Data register
                    tx_en <= 1;
                    tx_state <= 2;
                end
                
                2: begin  // Wait for transmission complete
                    tx_en <= 0;
                    if (!tx_rdy_n) begin
                        tx_pending <= 0;  // Clear pending
                        tx_state <= 0;
                    end
                end
                
                default: tx_state <= 0;
            endcase



            // Receive state machine
            command_valid <= 0;  // Reset command valid each cycle
            case (rx_state)
                0: begin  // Check if data is available
                    raddr <= 3'b000;  // Data register
                    rx_en <= 1;
                    if (!rx_rdy_n) begin  // Data is ready to be read
                        rx_state <= 1;
                    end
                end
                
                1: begin  // Read and process data
                    rx_en <= 0;
                    
                    case (rdata)
                        "t": begin  // Top command
                            state_desired <= TOP;
                            command_valid <= 1;
                            // Queue ACK response (higher priority than state updates)
                            if (tx_pending == 0 || tx_pending == 2'b11) begin
                                tx_pending <= 2'b01;
                            end
                        end

                        "p": begin  // Preload command
                            state_desired <= PRELOAD;
                            command_valid <= 1;
                            if (tx_pending == 0 || tx_pending == 2'b11) begin
                                tx_pending <= 2'b01;
                            end
                        end
                        
                        "i": begin  // Idle/Bottom command
                            state_desired <= IDLE;
                            command_valid <= 1;
                            if (tx_pending == 0 || tx_pending == 2'b11) begin
                                tx_pending <= 2'b01;
                            end
                        end
                        
                        "e": begin  // Delivery command
                            state_desired <= DELIVERY;
                            command_valid <= 1;
                            if (tx_pending == 0 || tx_pending == 2'b11) begin
                                tx_pending <= 2'b01;
                            end
                        end
                        
                        "u": begin  // Increment command
                            state_desired <= INCREMENT;
                            command_valid <= 1;
                            if (tx_pending == 0 || tx_pending == 2'b11) begin
                                tx_pending <= 2'b01;
                            end
                        end
                        
                        "d": begin  // Decrement command
                            state_desired <= DECREMENT;
                            command_valid <= 1;
                            if (tx_pending == 0 || tx_pending == 2'b11) begin
                                tx_pending <= 2'b01;
                            end
                        end
                        
                        default: begin
                            // Unknown command, no response
                        end
                    endcase
                    
                    rx_state <= 0;  // Go back to check for more data
                end
                
                default: rx_state <= 0;
            endcase
        end
    end

endmodule

