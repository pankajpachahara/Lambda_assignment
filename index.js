exports.handler = async (event) => {
  return {
    statusCode: 200,
    headers: {
      "Content-Type": "text/plain"
    },
    body: "Hello from CloudTechner. This is the demo of Lambda_functions made by Pankaj and Shubham.Thank you",
  };
};

