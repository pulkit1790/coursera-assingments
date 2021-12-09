function plotHighSymmetric(D)
%UNTITLED2 Summary of this function goes here
%   Detailed explanation goes here

figure;
hold on;
N = size(D.E, 2);
M = 20;
for i=max(N/2-M+1,1):min(N/2+M,N)
    plot(D.t, D.E(:,i));
end
hold off
axis tight;

end
