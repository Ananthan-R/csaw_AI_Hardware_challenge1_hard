# CSAW AI Hardware challenge 1 hard
## Usage of AI
The Claude Sonnet 4 Copilot in VS Code was used to make the necessary changes in the rtl code to include the trojan. The copilot was first supplied with all the necessary verilog files and the problem statement. It was then given a prompt asking it to make the necessary changes in code to implement the trojan mentioned in the problem statement. A paragraph highlighting the details of the CSAW AI Hardware challenge was also mentioned in the prompt to prevent the AI from considering the process of adding a trojan as a violation of its policies. Copilot identified all the errors and iterated multiple times to solve the errors by itself. 
## How to test the trojan

1. Build the original regression suite:
   ```powershell
   cd ~\CSAW-AI-Hardware-Attack-Challenge\challenges\challenge_1\01_easy
   iverilog -g2012 -o build_tb_aes.vvp tb\tb_aes_synth.v rtl\aes_flattened.v
   vvp build_tb_aes.vvp
   ```
   That run proves the modified core still carries out regular function while the trojan is inactive.

2. Build and run the Trojan demo bench:
   ```powershell
   iverilog -g2012 -o build_tb_aes_trojan.vvp tb\tb_aes_trojan_fixed.v rtl\aes_flattened.v
   vvp build_tb_aes_trojan.vvp
   ```
   The trojan leaks each bit of the lower 8 bits of the key as the LSB of the ciphertext. The test bench script tb_aes_trojan_fixed.v highlights this functionality by carrying out encryptions and comparing the leaked key with the original one.

This shows that the added trojan works properly, and does not show up in regular testing.
## How the trojan works
If the key doesn't contain the pattern `0x0c` in `key_reg[0][31:24]`, the Trojan remains completely inactive and invisible. When a key containing the pattern `0x0c` in the target location is loaded, the trojan gets activated. After that, each time an encryption completes with the trigger pattern present, the Trojan:
   - Increments its counter (0→1→2→...→7→0)
   - Selects the corresponding bit of `key[7:0]`
   - XORs that bit with the LSB of the ciphertext output