module top (
    input wire clk,          // 27MHz clock
    input wire up,           // Physical up button
    input wire down,         // Physical down button
    input wire rx,           // UART RX from external device
    output wire tx,          // UART TX to external device
    output wire pwm          // PWM output signal
);

    // Internal signals between UART and PWM modules
    wire [2:0] state_desired;
    wire uart_command_valid;
    wire target_reached;
    wire [7:0] current_state_msg;

    // PWM module instance
    pwm pwm_inst (
        .clk(clk),
        .up(up),
        .down(down),
        .state_desired(state_desired),
        .uart_command_valid(uart_command_valid),
        .target_reached(target_reached),
        .current_state_msg(current_state_msg),
        .moving(),  // Not connected - internal to PWM
        .pwm(pwm)
    );

    // UART module instance
    uart uart_inst (
        .clk(clk),
        .rx(rx),
        .target_reached(target_reached),
        .tx(tx),
        .state_desired(state_desired),
        .current_state_msg(current_state_msg),
        .command_valid(uart_command_valid)
    );

endmodule
