module dff (
    input wire clk,
    input wire rst,
    input wire d,
    output reg q
);

    always_combin
        if (rst)
            q <= 0;
        else
            q <= d;
    end

endmodule