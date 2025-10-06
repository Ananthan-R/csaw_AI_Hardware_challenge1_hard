/*
 * Simplified Testbench for AES Trojan Logic
 * 
 * This testbench directly tests the Trojan components without
 * running full AES encryptions, making it faster and easier to debug.
 */

`timescale 1ns / 1ps

module tb_trojan_simple();

    // Clock and reset
    reg clk;
    reg reset_n;
    
    // Testbench signals
    reg cs, we;
    reg [7:0] address;
    reg [31:0] write_data;
    wire [31:0] read_data;
    
    // Test variables
    reg [127:0] test_key;
    reg [7:0] expected_leaked_bits;
    reg [7:0] actual_leaked_bits;
    integer i;
    
    // Instantiate AES with Trojan
    aes dut (
        .clk(clk),
        .reset_n(reset_n),
        .cs(cs),
        .we(we),
        .address(address),
        .write_data(write_data),
        .read_data(read_data)
    );
    
    // Clock generation (10ns period = 100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Main test
    initial begin
        $display("=== Simplified Trojan Test Started ===");
        
        // Initialize
        reset_n = 0;
        cs = 0;
        we = 0;
        address = 8'h00;
        write_data = 32'h00000000;
        
        // Reset
        #50;
        reset_n = 1;
        #50;
        
        // Set test key with known pattern that will trigger the Trojan
        // The trigger activates when key_reg[0][31:24] == 0x0c
        // key_reg[0] gets test_key[31:0], so we need 0x0c in bits [31:24] of key_reg[0]
        test_key = 128'h000102030405060708090a0b0c0d0e0f;
        expected_leaked_bits = test_key[7:0]; // Should be 0x0f = 0b00001111
        
        // Adjust key so that key_reg[0][31:24] = 0x0c
        test_key[31:24] = 8'h0c;  // This will make the trigger activate
        expected_leaked_bits = test_key[7:0]; // Update expected bits
        
        $display("Test key: %032h", test_key);
        $display("Key_reg[0] will get: %08h", test_key[31:0]);
        $display("Key_reg[0][31:24] = %02h (trigger pattern: 0x0c)", test_key[31:24]);
        $display("Expected leaked bits (key[7:0]): %02h = %08b", expected_leaked_bits, expected_leaked_bits);
        
        // Load key into key registers (simulate key loading)
        write_key_register(8'h10, test_key[31:0]);   // key_reg[0]
        write_key_register(8'h11, test_key[63:32]);  // key_reg[1]
        write_key_register(8'h12, test_key[95:64]);  // key_reg[2]
        write_key_register(8'h13, test_key[127:96]); // key_reg[3]
        
        $display("Key loaded. Trojan counter: %0d", dut.trojan_counter_reg);
        $display("Key reg[0]: %08h (contains bits to leak)", dut.\key_reg[0] );
        
        // Simulate 8 encryption completions by directly toggling the valid signal
        $display("=== Simulating 8 encryption cycles ===");
        
        for (i = 0; i < 8; i = i + 1) begin
            $display("--- Cycle %0d ---", i + 1);
            $display("Counter before: %0d", dut.trojan_counter_reg);
            $display("Key bit to leak: %0d (bit %0d)", dut.\key_reg[0] [i], i);
            $display("Selected key bit: %0d", dut.trojan_key_bit);
            
            // Record the leaked bit BEFORE the counter increments
            actual_leaked_bits[i] = dut.trojan_key_bit;
            
            // Simulate encryption completion by pulsing the core result valid
            force dut.\core.result_valid_reg  = 1;
            #10;
            force dut.\core.result_valid_reg  = 0;
            #10;
            
            // Check counter increment
            $display("Counter after: %0d", dut.trojan_counter_reg);
            $display("Leaked bit %0d: %0d", i, actual_leaked_bits[i]);
        end
        
        // Release forced signals
        release dut.\core.result_valid_reg ;
        
        $display("=== Results ===");
        $display("Expected: %08b (%02h)", expected_leaked_bits, expected_leaked_bits);
        $display("Actual:   %08b (%02h)", actual_leaked_bits, actual_leaked_bits);
        
        if (actual_leaked_bits == expected_leaked_bits) begin
            $display("SUCCESS: Trojan correctly leaked all key bits!");
        end else begin
            $display("FAILURE: Mismatch in leaked bits");
            for (i = 0; i < 8; i = i + 1) begin
                if (actual_leaked_bits[i] == expected_leaked_bits[i])
                    $display("  Bit %0d: PASS (%0d)", i, actual_leaked_bits[i]);
                else
                    $display("  Bit %0d: FAIL (got %0d, expected %0d)", i, actual_leaked_bits[i], expected_leaked_bits[i]);
            end
        end
        
        $display("=== Test Complete ===");
        $finish;
    end
    
    // Task to write to key registers
    task write_key_register;
        input [7:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            cs = 1;
            we = 1;
            address = addr;
            write_data = data;
            @(posedge clk);
            cs = 0;
            we = 0;
            #10;
        end
    endtask
    
    // Monitor key changes
    always @(posedge clk) begin
        if (dut.trojan_enc_done)
            $display("[Monitor] Encryption done detected! Counter will increment.");
    end

endmodule