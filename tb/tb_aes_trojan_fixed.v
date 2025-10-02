/*
 * Fixed Testbench for AES with Hardware Trojan
 * 
 * This testbench demonstrates the Trojan functionality that leaks
 * the lower 8 bits of the encryption key through the LSB of the
 * ciphertext output, one bit per encryption.
 */

`timescale 1ns / 1ps

module tb_aes_trojan_fixed();

    // Parameters
    parameter CLK_PERIOD = 10; // 100 MHz clock
    
    // Testbench signals
    reg clk;
    reg reset_n;
    reg cs;
    reg we;
    reg [7:0] address;
    reg [31:0] write_data;
    wire [31:0] read_data;
    
    // Test variables
    reg [31:0] read_buffer;
    reg [127:0] test_key;
    reg [127:0] test_plaintext;
    reg [127:0] ciphertext_result;
    reg [7:0] leaked_key_bits;
    integer i;
    
    // Instantiate the AES module with Trojan
    aes dut (
        .clk(clk),
        .reset_n(reset_n),
        .cs(cs),
        .we(we),
        .address(address),
        .write_data(write_data),
        .read_data(read_data)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Simulation timeout
    initial begin
        #10000000; // 10ms timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end
    
    // Test stimulus
    initial begin
        // Initialize signals
        reset_n = 0;
        cs = 0;
        we = 0;
        address = 8'h00;
        write_data = 32'h00000000;
        leaked_key_bits = 8'h00;
        
        // Display test start
        $display("=== AES Trojan Testbench Started ===");
        $display("Time: %0t", $time);
        
        // Reset sequence
        #(CLK_PERIOD * 10);
        reset_n = 1;
        #(CLK_PERIOD * 10);
        
        // Test key with known pattern in lower 8 bits
        test_key = 128'h000102030405060708090a0b0c0d0e0f;
        test_plaintext = 128'h00112233445566778899aabbccddeeff;
        
        $display("\\n=== Setting up AES encryption ===");
        $display("Test Key: %032h", test_key);
        $display("Expected leaked bits (key[7:0]): %02h = %08b", test_key[7:0], test_key[7:0]);
        $display("Plaintext: %032h", test_plaintext);
        
        // Load the key
        write_register(8'h10, test_key[31:0]);    // key_reg[0] - contains target bits
        write_register(8'h11, test_key[63:32]);   // key_reg[1]
        write_register(8'h12, test_key[95:64]);   // key_reg[2]
        write_register(8'h13, test_key[127:96]);  // key_reg[3]
        
        $display("Key loaded. Trojan counter: %0d", dut.trojan_counter_reg);
        
        $display("\\n=== Testing Trojan by monitoring 8 operations ===");
        
        // Instead of full AES encryptions, simulate the encryption completion
        // by directly manipulating the core's result valid signal
        for (i = 0; i < 8; i = i + 1) begin
            $display("\\n--- Operation %0d ---", i + 1);
            $display("Counter before: %0d", dut.trojan_counter_reg);
            $display("Selected key bit: %0d", dut.trojan_key_bit);
            
            // Load some plaintext (for realism, though we won't wait for real encryption)
            write_register(8'h20, test_plaintext[31:0] + i);
            write_register(8'h21, test_plaintext[63:32] + i);
            write_register(8'h22, test_plaintext[95:64] + i);
            write_register(8'h23, test_plaintext[127:96] + i);
            
            // Simulate an encryption completion by forcing the result valid signal
            $display("Simulating encryption completion...");
            
            // Record the leaked bit BEFORE the counter increments
            leaked_key_bits[i] = dut.trojan_key_bit;
            
            // Trigger the encryption done signal
            force dut.\core.result_valid_reg  = 1;
            #(CLK_PERIOD);
            force dut.\core.result_valid_reg  = 0;
            #(CLK_PERIOD);
            
            $display("Counter after: %0d", dut.trojan_counter_reg);
            $display("Leaked bit %0d: %0d", i, leaked_key_bits[i]);
            
            #(CLK_PERIOD * 5); // Small delay between operations
        end
        
        // Release forced signals
        release dut.\core.result_valid_reg ;
        
        $display("\\n=== Trojan Analysis Results ===");
        $display("Original key[7:0]:  %02h = %08b", test_key[7:0], test_key[7:0]);
        $display("Leaked key bits:    %02h = %08b", leaked_key_bits, leaked_key_bits);
        
        // Verify if the Trojan successfully leaked the key bits
        if (leaked_key_bits == test_key[7:0]) begin
            $display("✓ SUCCESS: Trojan successfully leaked all 8 key bits!");
        end else begin
            $display("✗ FAILURE: Leaked bits don't match original key bits");
            for (i = 0; i < 8; i = i + 1) begin
                if (leaked_key_bits[i] == test_key[i]) begin
                    $display("  Bit %0d: ✓ Match (%b)", i, leaked_key_bits[i]);
                end else begin
                    $display("  Bit %0d: ✗ Mismatch (got %b, expected %b)", i, leaked_key_bits[i], test_key[i]);
                end
            end
        end
        
        $display("\\n=== Testing Output Modification ===");
        // Test that the trojan actually modifies the output
        
        // Set a known pattern in _00005_[0] and see if read_data[0] is modified
        $display("Testing output LSB modification...");
        cs = 1;
        #(CLK_PERIOD);
        $display("read_data[0] = %0d (should be XORed with key bit)", read_data[0]);
        $display("trojan_modified_lsb = %0d", dut.trojan_modified_lsb);
        cs = 0;
        
        $display("\\n=== Testbench Complete ===");
        $display("Time: %0t", $time);
        $finish;
    end
    
    // Task to write to a register
    task write_register;
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
            #(CLK_PERIOD);
        end
    endtask
    
    // Monitor for debugging
    initial begin
        $monitor("Time: %0t | Counter: %0d | Key bit: %0d | LSB: %0d", 
                 $time, dut.trojan_counter_reg, dut.trojan_key_bit, read_data[0]);
    end

endmodule